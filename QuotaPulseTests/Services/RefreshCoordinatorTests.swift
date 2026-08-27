import XCTest
@testable import QuotaPulse

final class RefreshCoordinatorTests: XCTestCase {
    func testConcurrentRefreshesShareOneProviderFetch() async {
        let counter = InvocationCounter()
        let provider = CountingProvider(counter: counter)
        let service = UsageService(providers: [provider])
        let coordinator = RefreshCoordinator(usageService: service)

        async let first = coordinator.refresh()
        await Task.yield()
        async let second = coordinator.refresh()

        let (firstStates, secondStates) = await (first, second)
        let invocationCount = await counter.value

        XCTAssertEqual(invocationCount, 1)
        XCTAssertEqual(firstStates, secondStates)
        XCTAssertEqual(firstStates.first?.status, .available)
    }

    func testCancelledRefreshRemainsInFlightUntilProviderFinishes() async {
        let counter = InvocationCounter()
        let gate = ProviderGate()
        let provider = GatedProvider(counter: counter, gate: gate)
        let service = UsageService(providers: [provider])
        let coordinator = RefreshCoordinator(usageService: service)

        async let first = coordinator.refresh()
        await counter.waitForInvocation()
        await coordinator.cancel()
        async let second = coordinator.refresh()
        await Task.yield()

        let invocationCountBeforeOpeningGate = await counter.value
        XCTAssertEqual(invocationCountBeforeOpeningGate, 1)

        await gate.open()
        let (firstStates, secondStates) = await (first, second)

        let finalInvocationCount = await counter.value
        XCTAssertEqual(finalInvocationCount, 1)
        XCTAssertEqual(firstStates, secondStates)
    }
}

private actor InvocationCounter {
    private(set) var value = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func increment() {
        value += 1
        let pendingWaiters = waiters
        waiters.removeAll()
        pendingWaiters.forEach { $0.resume() }
    }

    func waitForInvocation() async {
        guard value == 0 else { return }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }
}

private actor ProviderGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func open() {
        isOpen = true
        let pendingWaiters = waiters
        waiters.removeAll()
        pendingWaiters.forEach { $0.resume() }
    }
}

private struct CountingProvider: UsageProvider {
    let id = ProviderID.codex
    let counter: InvocationCounter

    func fetchUsage() async throws -> ProviderUsageSnapshot {
        await counter.increment()
        try await Task.sleep(for: .milliseconds(100))

        return ProviderUsageSnapshot(
            providerID: id,
            windows: [],
            capturedAt: Date(timeIntervalSince1970: 1_000_000),
            source: UsageSource(kind: .mock, label: "Test", documentationURL: nil)
        )
    }
}

private struct GatedProvider: UsageProvider {
    let id = ProviderID.codex
    let counter: InvocationCounter
    let gate: ProviderGate

    func fetchUsage() async throws -> ProviderUsageSnapshot {
        await counter.increment()
        await gate.wait()

        return ProviderUsageSnapshot(
            providerID: id,
            windows: [],
            capturedAt: Date(timeIntervalSince1970: 1_000_000),
            source: UsageSource(kind: .mock, label: "Test", documentationURL: nil)
        )
    }
}
