import Foundation
import XCTest
@testable import QuotaPulse

final class UsageServiceTests: XCTestCase {
    func testRefreshesMultipleProvidersInConfiguredOrder() async {
        let codex = StubUsageProvider(
            id: .codex,
            result: .success(makeSnapshot(providerID: .codex, usedPercentage: 25))
        )
        let claude = StubUsageProvider(
            id: .claude,
            result: .success(makeSnapshot(providerID: .claude, usedPercentage: 40))
        )
        let service = UsageService(providers: [codex, claude])

        let states = await service.refresh()

        XCTAssertEqual(states.map(\.providerID), [.codex, .claude])
        XCTAssertEqual(states.map(\.status), [.available, .available])
        XCTAssertEqual(states[0].snapshot?.windows[0].remainingPercentage, 75)
        XCTAssertEqual(states[1].snapshot?.windows[0].remainingPercentage, 60)
    }

    func testOneProviderFailureDoesNotPreventAnotherProviderFromSucceeding() async {
        let codex = StubUsageProvider(
            id: .codex,
            result: .failure(TestProviderStatusError(providerStatus: .notInstalled))
        )
        let claudeSnapshot = makeSnapshot(providerID: .claude, usedPercentage: 40)
        let claude = StubUsageProvider(id: .claude, result: .success(claudeSnapshot))
        let service = UsageService(providers: [codex, claude])

        let states = await service.refresh()

        XCTAssertEqual(states.count, 2)
        XCTAssertEqual(states[0].status, .notInstalled)
        XCTAssertNil(states[0].snapshot)
        XCTAssertEqual(states[1].status, .available)
        XCTAssertEqual(states[1].snapshot, claudeSnapshot)
    }

    func testLaterProviderFailureDoesNotDiscardEarlierProviderSuccess() async {
        let codexSnapshot = makeSnapshot(providerID: .codex, usedPercentage: 25)
        let codex = StubUsageProvider(id: .codex, result: .success(codexSnapshot))
        let claude = StubUsageProvider(
            id: .claude,
            result: .failure(
                TestProviderStatusError(
                    providerStatus: .failed(.refreshFailed)
                )
            )
        )
        let service = UsageService(providers: [codex, claude])

        let states = await service.refresh()

        XCTAssertEqual(states.count, 2)
        XCTAssertEqual(states[0].status, .available)
        XCTAssertEqual(states[0].snapshot, codexSnapshot)
        XCTAssertEqual(
            states[1].status,
            .failed(.refreshFailed)
        )
        XCTAssertNil(states[1].snapshot)
    }

    func testBothProviderFailuresKeepIndependentErrorStates() async {
        let codex = StubUsageProvider(
            id: .codex,
            result: .failure(
                TestProviderStatusError(
                    providerStatus: .failed(.refreshFailed)
                )
            )
        )
        let claude = StubUsageProvider(
            id: .claude,
            result: .failure(
                TestProviderStatusError(
                    providerStatus: .failed(.refreshFailed)
                )
            )
        )
        let service = UsageService(providers: [codex, claude])

        let states = await service.refresh()

        XCTAssertEqual(states.map(\.providerID), [.codex, .claude])
        XCTAssertEqual(
            states.map(\.status),
            [
                .failed(.refreshFailed),
                .failed(.refreshFailed),
            ]
        )
        XCTAssertTrue(states.allSatisfy { $0.snapshot == nil })
    }

    func testBothUnavailableProvidersKeepIndependentNormalizedStates() async {
        let codex = StubUsageProvider(
            id: .codex,
            result: .failure(TestProviderStatusError(providerStatus: .notInstalled))
        )
        let claude = StubUsageProvider(
            id: .claude,
            result: .failure(TestProviderStatusError(providerStatus: .notConfigured))
        )
        let service = UsageService(providers: [codex, claude])

        let states = await service.refresh()

        XCTAssertEqual(states.map(\.providerID), [.codex, .claude])
        XCTAssertEqual(states.map(\.status), [.notInstalled, .notConfigured])
        XCTAssertTrue(states.allSatisfy { $0.snapshot == nil })
    }

    func testEveryRefreshFetchesEveryProviderAgain() async {
        let codexCounter = FetchCounter()
        let claudeCounter = FetchCounter()
        let service = UsageService(providers: [
            CountingUsageProvider(id: .codex, counter: codexCounter),
            CountingUsageProvider(id: .claude, counter: claudeCounter),
        ])

        _ = await service.refresh()
        _ = await service.refresh()

        let codexFetchCount = await codexCounter.value
        let claudeFetchCount = await claudeCounter.value
        XCTAssertEqual(codexFetchCount, 2)
        XCTAssertEqual(claudeFetchCount, 2)
    }

    func testRejectsSnapshotWhoseIdentityDoesNotMatchItsProvider() async {
        let provider = StubUsageProvider(
            id: .codex,
            result: .success(makeSnapshot(providerID: .claude, usedPercentage: 40))
        )
        let service = UsageService(providers: [provider])

        let states = await service.refresh()

        XCTAssertEqual(
            states,
            [
                ProviderState(
                    providerID: .codex,
                    status: .failed(.refreshFailed),
                    snapshot: nil
                )
            ]
        )
    }

    private func makeSnapshot(
        providerID: ProviderID,
        usedPercentage: Double
    ) -> ProviderUsageSnapshot {
        ProviderUsageSnapshot(
            providerID: providerID,
            windows: [
                UsageWindow(
                    id: "\(providerID.rawValue).window",
                    label: "Test window",
                    usedPercentage: usedPercentage,
                    resetAt: Date(timeIntervalSince1970: 2_000_003_600),
                    duration: .seconds(18_000)
                )
            ],
            capturedAt: Date(timeIntervalSince1970: 2_000_000_000),
            source: UsageSource(kind: .mock, label: "Test", documentationURL: nil)
        )
    }
}

private struct StubUsageProvider: UsageProvider {
    let id: ProviderID
    let result: Result<ProviderUsageSnapshot, Error>

    func fetchUsage() async throws -> ProviderUsageSnapshot {
        try result.get()
    }
}

private struct TestProviderStatusError: ProviderStatusProvidingError {
    let providerStatus: ProviderStatus
}

private actor FetchCounter {
    private(set) var value = 0

    func next() -> Int {
        value += 1
        return value
    }
}

private struct CountingUsageProvider: UsageProvider {
    let id: ProviderID
    let counter: FetchCounter

    func fetchUsage() async throws -> ProviderUsageSnapshot {
        let count = await counter.next()
        return ProviderUsageSnapshot(
            providerID: id,
            windows: [],
            capturedAt: Date(timeIntervalSince1970: TimeInterval(count)),
            source: UsageSource(kind: .mock, label: "Test", documentationURL: nil)
        )
    }
}
