import Foundation
import XCTest
@testable import QuotaPulse

@MainActor
final class RefreshLifecycleTests: XCTestCase {
    private let policy = RefreshPolicy.v01

    func testScheduledAutomaticRefreshUsesFifteenMinuteInterval() async throws {
        let state = LifecycleProviderState()
        let sleeper = ControlledRefreshSleeper()
        let model = makeModel(provider: LifecycleProvider(state: state), sleeper: sleeper)

        await model.refresh()
        await sleeper.waitForRequestCount(1)

        let initialInvocationCount = await state.invocationCount
        let initialDuration = await sleeper.latestDurationSeconds
        XCTAssertEqual(initialInvocationCount, 1)
        XCTAssertEqual(try XCTUnwrap(initialDuration), 15 * 60, accuracy: 0.01)

        await sleeper.resumeNext()
        await state.waitForInvocationCount(2)
        await sleeper.waitForRequestCount(2)

        let finalInvocationCount = await state.invocationCount
        let finalDuration = await sleeper.latestDurationSeconds
        XCTAssertEqual(finalInvocationCount, 2)
        XCTAssertEqual(try XCTUnwrap(finalDuration), 15 * 60, accuracy: 0.01)
    }

    func testManualRefreshRunsImmediately() async {
        let state = LifecycleProviderState()
        let sleeper = ControlledRefreshSleeper()
        let model = makeModel(provider: LifecycleProvider(state: state), sleeper: sleeper)

        await model.refresh()
        await model.refresh()

        let invocationCount = await state.invocationCount
        XCTAssertEqual(invocationCount, 2)
    }

    func testRepeatedManualRefreshWhileRefreshIsInFlightDoesNotOverlap() async {
        let state = LifecycleProviderState(blockedInvocations: [1])
        let sleeper = ControlledRefreshSleeper()
        let model = makeModel(provider: LifecycleProvider(state: state), sleeper: sleeper)

        model.refreshManually()
        await state.waitForInvocationCount(1)

        for _ in 0..<20 {
            model.refreshManually()
        }

        var invocationCount = await state.invocationCount
        var maximumConcurrentFetches = await state.maximumConcurrentFetches
        XCTAssertEqual(invocationCount, 1)
        XCTAssertEqual(maximumConcurrentFetches, 1)

        await state.unblockInvocation(1)
        await waitUntilRefreshFinishes(model)

        invocationCount = await state.invocationCount
        maximumConcurrentFetches = await state.maximumConcurrentFetches
        XCTAssertEqual(invocationCount, 1)
        XCTAssertEqual(maximumConcurrentFetches, 1)
    }

    func testAutomaticMenuRefreshWhileManualRefreshIsInFlightDoesNotOverlap() async {
        let clock = TestDateSource(Date(timeIntervalSince1970: 2_000_000_000))
        let state = LifecycleProviderState(blockedInvocations: [2], now: clock.current)
        let sleeper = ControlledRefreshSleeper()
        let model = makeModel(
            provider: LifecycleProvider(state: state),
            sleeper: sleeper,
            now: clock.current
        )

        await model.refresh()
        clock.advance(by: policy.menuStaleThreshold)
        model.refreshManually()
        await state.waitForInvocationCount(2)

        for _ in 0..<20 {
            model.menuDidOpen()
        }

        var invocationCount = await state.invocationCount
        var maximumConcurrentFetches = await state.maximumConcurrentFetches
        XCTAssertEqual(invocationCount, 2)
        XCTAssertEqual(maximumConcurrentFetches, 1)

        await state.unblockInvocation(2)
        await waitUntilRefreshFinishes(model)

        invocationCount = await state.invocationCount
        maximumConcurrentFetches = await state.maximumConcurrentFetches
        XCTAssertEqual(invocationCount, 2)
        XCTAssertEqual(maximumConcurrentFetches, 1)
    }

    func testRetryBackoffAdvancesAndResetsAfterRecovery() async throws {
        let state = LifecycleProviderState(
            outcomes: [
                .failure(LifecycleProviderError.failed),
                .failure(LifecycleProviderError.failed),
                .success,
            ]
        )
        let sleeper = ControlledRefreshSleeper()
        let model = makeModel(provider: LifecycleProvider(state: state), sleeper: sleeper)

        await model.refresh()
        await sleeper.waitForRequestCount(1)
        var latestDuration = await sleeper.latestDurationSeconds
        XCTAssertEqual(try XCTUnwrap(latestDuration), 60, accuracy: 0.01)

        await sleeper.resumeNext()
        await state.waitForInvocationCount(2)
        await sleeper.waitForRequestCount(2)
        latestDuration = await sleeper.latestDurationSeconds
        XCTAssertEqual(try XCTUnwrap(latestDuration), 2 * 60, accuracy: 0.01)

        await sleeper.resumeNext()
        await state.waitForInvocationCount(3)
        await sleeper.waitForRequestCount(3)

        XCTAssertEqual(model.providerStates.first?.status, .available)
        latestDuration = await sleeper.latestDurationSeconds
        XCTAssertEqual(try XCTUnwrap(latestDuration), 15 * 60, accuracy: 0.01)
    }

    func testRetryBackoffCapsAtThirtyMinutes() {
        XCTAssertEqual(
            (1...7).map { policy.nextRefreshDelay(consecutiveFailureCount: $0) },
            [60, 120, 300, 900, 1_800, 1_800, 1_800]
        )
    }

    func testCountdownCalculationDoesNotFetchProviderData() async {
        let state = LifecycleProviderState()
        let sleeper = ControlledRefreshSleeper()
        let model = makeModel(provider: LifecycleProvider(state: state), sleeper: sleeper)
        let now = Date(timeIntervalSince1970: 2_000_000_000)

        await model.refresh()

        XCTAssertEqual(
            ResetCountdown.text(
                until: now.addingTimeInterval(10 * 60),
                now: now,
                locale: Locale(identifier: "en")
            ),
            "10 min"
        )
        XCTAssertEqual(
            ResetCountdown.text(
                until: now.addingTimeInterval(10 * 60),
                now: now.addingTimeInterval(60),
                locale: Locale(identifier: "en")
            ),
            "9 min"
        )
        let invocationCount = await state.invocationCount
        XCTAssertEqual(invocationCount, 1)
    }

    func testRepeatedFreshMenuOpenDoesNotAccumulateRefreshOrScheduleTasks() async {
        let clock = TestDateSource(Date(timeIntervalSince1970: 2_000_000_000))
        let state = LifecycleProviderState(now: clock.current)
        let sleeper = ControlledRefreshSleeper()
        let model = makeModel(
            provider: LifecycleProvider(state: state),
            sleeper: sleeper,
            now: clock.current
        )

        await model.refresh()
        await sleeper.waitForRequestCount(1)

        for _ in 0..<200 {
            model.menuDidOpen()
        }

        var invocationCount = await state.invocationCount
        var activeRequestCount = await sleeper.activeRequestCount
        XCTAssertEqual(invocationCount, 1)
        XCTAssertEqual(activeRequestCount, 1)

        clock.advance(by: policy.menuStaleThreshold)
        for _ in 0..<200 {
            model.menuDidOpen()
        }
        await state.waitForInvocationCount(2)
        await sleeper.waitForRequestCount(2)

        invocationCount = await state.invocationCount
        let maximumConcurrentFetches = await state.maximumConcurrentFetches
        activeRequestCount = await sleeper.activeRequestCount
        XCTAssertEqual(invocationCount, 2)
        XCTAssertEqual(maximumConcurrentFetches, 1)
        XCTAssertEqual(activeRequestCount, 1)
    }

    func testStaleMenuOpenKeepsCachedSnapshotVisibleWhileRefreshingInBackground() async throws {
        let clock = TestDateSource(Date(timeIntervalSince1970: 2_000_000_000))
        let state = LifecycleProviderState(blockedInvocations: [2], now: clock.current)
        let sleeper = ControlledRefreshSleeper()
        let model = makeModel(
            provider: LifecycleProvider(state: state),
            sleeper: sleeper,
            now: clock.current
        )

        await model.refresh()
        let cachedSnapshot = try XCTUnwrap(model.providerStates.first?.snapshot)
        clock.advance(by: policy.menuStaleThreshold)

        model.menuDidOpen()

        XCTAssertEqual(model.providerStates.first?.status, .loading)
        XCTAssertEqual(model.providerStates.first?.snapshot, cachedSnapshot)
        await state.waitForInvocationCount(2)

        await state.unblockInvocation(2)
        await waitUntilRefreshFinishes(model)
    }

    func testSleepWakeAndActivationResumeExactlyOneSchedule() async {
        let clock = TestDateSource(Date(timeIntervalSince1970: 2_000_000_000))
        let state = LifecycleProviderState(now: clock.current)
        let sleeper = ControlledRefreshSleeper()
        let model = makeModel(
            provider: LifecycleProvider(state: state),
            sleeper: sleeper,
            now: clock.current
        )

        await model.refresh()
        await sleeper.waitForRequestCount(1)

        model.systemWillSleep()
        await sleeper.waitForActiveRequestCount(0)
        clock.advance(by: policy.normalBackgroundInterval + 1)

        for _ in 0..<10 {
            model.systemDidWake()
            model.applicationDidBecomeActive()
        }
        await state.waitForInvocationCount(2)
        await sleeper.waitForRequestCount(2)

        let invocationCount = await state.invocationCount
        let maximumConcurrentFetches = await state.maximumConcurrentFetches
        let activeRequestCount = await sleeper.activeRequestCount
        XCTAssertEqual(invocationCount, 2)
        XCTAssertEqual(maximumConcurrentFetches, 1)
        XCTAssertEqual(activeRequestCount, 1)
    }

    func testRepeatedMenuOpenDoesNotRereadAnAlreadyStaleSourceImmediately() async {
        let clock = TestDateSource(Date(timeIntervalSince1970: 2_000_000_000))
        let state = LifecycleProviderState(now: { clock.current().addingTimeInterval(-900) })
        let sleeper = ControlledRefreshSleeper()
        let model = makeModel(
            provider: LifecycleProvider(state: state),
            sleeper: sleeper,
            now: clock.current
        )

        await model.refresh()
        for _ in 0..<20 {
            model.menuDidOpen()
            await Task.yield()
        }
        var invocationCount = await state.invocationCount
        XCTAssertEqual(invocationCount, 1)

        clock.advance(by: policy.menuStaleThreshold)
        model.menuDidOpen()
        await state.waitForInvocationCount(2)
        await waitUntilRefreshFinishes(model)
        invocationCount = await state.invocationCount
        XCTAssertEqual(invocationCount, 2)
    }

    func testMenuOpenRespectsBackoffWhileAnotherProviderRemainsFunctional() async {
        let clock = TestDateSource(Date(timeIntervalSince1970: 2_000_000_000))
        let failedState = LifecycleProviderState(
            outcomes: Array(repeating: .failure(.failed), count: 3),
            now: clock.current
        )
        let healthyState = LifecycleProviderState(now: { clock.current().addingTimeInterval(-900) })
        let sleeper = ControlledRefreshSleeper()
        let model = makeModel(
            provider: LifecycleProvider(state: failedState),
            additionalProviders: [LifecycleProvider(state: healthyState, id: .claude)],
            sleeper: sleeper,
            now: clock.current
        )

        for _ in 0..<3 {
            await model.refresh()
        }
        XCTAssertEqual(model.providerStates.last?.status, .available)
        clock.advance(by: policy.menuStaleThreshold + 1)
        for _ in 0..<20 {
            model.menuDidOpen()
            await Task.yield()
        }
        let failedInvocationCount = await failedState.invocationCount
        let healthyInvocationCount = await healthyState.invocationCount
        XCTAssertEqual(failedInvocationCount, 3)
        XCTAssertEqual(healthyInvocationCount, 3)

        await model.refresh()
        XCTAssertEqual(model.providerStates.map(\.status), [.available, .available])
    }

    private func makeModel(
        provider: any UsageProvider,
        additionalProviders: [any UsageProvider] = [],
        sleeper: ControlledRefreshSleeper,
        now: @escaping @Sendable () -> Date = Date.init
    ) -> AppModel {
        let providers = [provider] + additionalProviders
        return AppModel(
            providerIDs: providers.map(\.id),
            refreshCoordinator: RefreshCoordinator(
                usageService: UsageService(providers: providers)
            ),
            notificationService: LifecycleNotificationService(),
            refreshPolicy: policy,
            refreshSleeper: sleeper,
            now: now,
            observesLifecycle: false
        )
    }

    private func waitUntilRefreshFinishes(_ model: AppModel) async {
        while model.isRefreshing {
            await Task.yield()
        }
    }
}

private enum LifecycleProviderError: Error, ProviderStatusProvidingError {
    case failed

    var providerStatus: ProviderStatus {
        .failed(.refreshFailed)
    }
}

private actor LifecycleProviderState {
    enum Outcome: Sendable {
        case success
        case failure(LifecycleProviderError)
    }

    private(set) var invocationCount = 0
    private(set) var maximumConcurrentFetches = 0
    private var concurrentFetches = 0
    private var blockedInvocations: Set<Int>
    private var unblockWaiters: [Int: CheckedContinuation<Void, Never>] = [:]
    private var invocationWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
    private var outcomes: [Outcome]
    private let now: @Sendable () -> Date

    init(
        blockedInvocations: Set<Int> = [],
        outcomes: [Outcome] = [],
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.blockedInvocations = blockedInvocations
        self.outcomes = outcomes
        self.now = now
    }

    func fetch(providerID: ProviderID) async throws -> ProviderUsageSnapshot {
        invocationCount += 1
        let invocation = invocationCount
        concurrentFetches += 1
        maximumConcurrentFetches = max(maximumConcurrentFetches, concurrentFetches)

        let readyWaiters = invocationWaiters.filter { $0.count <= invocationCount }
        invocationWaiters.removeAll { $0.count <= invocationCount }
        readyWaiters.forEach { $0.continuation.resume() }

        if blockedInvocations.contains(invocation) {
            await withCheckedContinuation { continuation in
                unblockWaiters[invocation] = continuation
            }
        }

        defer { concurrentFetches -= 1 }
        let outcome = outcomes.isEmpty ? .success : outcomes.removeFirst()
        if case let .failure(error) = outcome {
            throw error
        }

        return ProviderUsageSnapshot(
            providerID: providerID,
            windows: [
                UsageWindow(
                    id: "\(providerID.rawValue).window",
                    label: "Test window",
                    usedPercentage: 25,
                    resetAt: now().addingTimeInterval(3_600),
                    duration: .seconds(18_000)
                )
            ],
            capturedAt: now(),
            source: UsageSource(kind: .mock, label: "Test", documentationURL: nil)
        )
    }

    func waitForInvocationCount(_ count: Int) async {
        guard invocationCount < count else { return }
        await withCheckedContinuation { continuation in
            invocationWaiters.append((count, continuation))
        }
    }

    func unblockInvocation(_ invocation: Int) {
        blockedInvocations.remove(invocation)
        unblockWaiters.removeValue(forKey: invocation)?.resume()
    }
}

private struct LifecycleProvider: UsageProvider {
    let id: ProviderID
    let state: LifecycleProviderState

    init(state: LifecycleProviderState, id: ProviderID = .codex) {
        self.state = state
        self.id = id
    }

    func fetchUsage() async throws -> ProviderUsageSnapshot {
        try await state.fetch(providerID: id)
    }
}

private actor ControlledRefreshSleeper: RefreshSleeping {
    private struct Request {
        let id: UUID
        let duration: Duration
        let continuation: CheckedContinuation<Void, Error>
    }

    private var requests: [Request] = []
    private var cancelledRequestIDs: Set<UUID> = []
    private var requestCount = 0
    private var requestWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
    private var activeCountWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    var latestDurationSeconds: Double? {
        guard let duration = requests.last?.duration else { return nil }
        let components = duration.components
        return Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
    var activeRequestCount: Int { requests.count }

    func sleep(for duration: Duration) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await suspend(id: id, duration: duration)
        } onCancel: {
            Task {
                await self.cancel(id: id)
            }
        }
    }

    func waitForRequestCount(_ count: Int) async {
        guard requestCount < count else { return }
        await withCheckedContinuation { continuation in
            requestWaiters.append((count, continuation))
        }
    }

    func waitForActiveRequestCount(_ count: Int) async {
        guard requests.count != count else { return }
        await withCheckedContinuation { continuation in
            activeCountWaiters.append((count, continuation))
        }
    }

    func resumeNext() {
        guard !requests.isEmpty else { return }
        let request = requests.removeFirst()
        request.continuation.resume()
        resumeActiveCountWaiters()
    }

    private func suspend(id: UUID, duration: Duration) async throws {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            if cancelledRequestIDs.remove(id) != nil {
                continuation.resume(throwing: CancellationError())
                return
            }

            requests.append(Request(id: id, duration: duration, continuation: continuation))
            requestCount += 1
            let readyWaiters = requestWaiters.filter { $0.count <= requestCount }
            requestWaiters.removeAll { $0.count <= requestCount }
            readyWaiters.forEach { $0.continuation.resume() }
            resumeActiveCountWaiters()
        }
    }

    private func cancel(id: UUID) {
        guard let index = requests.firstIndex(where: { $0.id == id }) else {
            cancelledRequestIDs.insert(id)
            return
        }

        let request = requests.remove(at: index)
        request.continuation.resume(throwing: CancellationError())
        resumeActiveCountWaiters()
    }

    private func resumeActiveCountWaiters() {
        let readyWaiters = activeCountWaiters.filter { $0.count == requests.count }
        activeCountWaiters.removeAll { $0.count == requests.count }
        readyWaiters.forEach { $0.continuation.resume() }
    }
}

private final class TestDateSource: @unchecked Sendable {
    private let lock = NSLock()
    private var date: Date

    init(_ date: Date) {
        self.date = date
    }

    func current() -> Date {
        lock.withLock { date }
    }

    func advance(by interval: TimeInterval) {
        lock.withLock {
            date = date.addingTimeInterval(interval)
        }
    }
}

@MainActor
private final class LifecycleNotificationService: NotificationServicing {
    func evaluate(_ providerStates: [ProviderState], now: Date) async {}
    func sendTestNotification() async throws {}
}
