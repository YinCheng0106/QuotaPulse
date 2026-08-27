#if DEBUG
import Darwin
import XCTest
@testable import QuotaPulse

final class RuntimeDiagnosticsTests: XCTestCase {
    func testSnapshotKeepsOnlyCurrentBoundedRuntimeState() {
        let diagnostics = RuntimeDiagnostics()
        let attempt = Date(timeIntervalSince1970: 2_000_000_000)
        let success = attempt.addingTimeInterval(2)
        let nextRefresh = success.addingTimeInterval(900)

        diagnostics.refreshStarted(at: attempt)
        diagnostics.providerRefreshStarted(.codex)
        diagnostics.providerRefreshStarted(.claude)
        diagnostics.codexProcessStarted(123)
        diagnostics.codexStdoutReaderStarted(processID: 123)
        diagnostics.codexConnectionBecameHealthy(processID: 123)
        diagnostics.providerRefreshFinished(.codex)
        diagnostics.providerRefreshFinished(.claude)
        diagnostics.refreshFinished(
            states: [
                ProviderState(providerID: .codex, status: .available, snapshot: nil),
                ProviderState(providerID: .claude, status: .notConfigured, snapshot: nil),
            ],
            at: success
        )
        diagnostics.schedulerUpdated(
            .scheduled,
            nextRefreshAt: nextRefresh,
            consecutiveFailureCount: 0
        )
        diagnostics.notificationsUpdated(pendingCount: 2, deduplicationEntryCount: 3)

        let snapshot = diagnostics.snapshot()

        XCTAssertNotNil(snapshot.memoryFootprintBytes)
        XCTAssertEqual(snapshot.activeAppRefreshes, 0)
        XCTAssertEqual(snapshot.maximumActiveAppRefreshes, 1)
        XCTAssertEqual(snapshot.activeProviderRefreshes, 0)
        XCTAssertEqual(snapshot.maximumActiveProviderRefreshes, 2)
        XCTAssertFalse(snapshot.isRefreshInFlight)
        XCTAssertEqual(snapshot.lastRefreshAttemptAt, attempt)
        XCTAssertEqual(snapshot.lastSuccessfulRefreshAt, success)
        XCTAssertEqual(snapshot.schedulerState, .scheduled)
        XCTAssertEqual(snapshot.refreshSchedulerCount, 1)
        XCTAssertEqual(snapshot.nextRefreshAt, nextRefresh)
        XCTAssertEqual(snapshot.codexConnectionState, "healthy")
        XCTAssertEqual(snapshot.codexProcessIDs, [123])
        XCTAssertEqual(snapshot.codexStdoutReaderCount, 1)
        XCTAssertEqual(snapshot.pendingNotificationCount, 2)
        XCTAssertEqual(snapshot.notificationDeduplicationEntryCount, 3)
        XCTAssertEqual(snapshot.providerAvailability["codex"], "available")
        XCTAssertEqual(snapshot.providerAvailability["claude"], "not_configured")
    }

    func testCodexProcessAndReaderCleanupAreIdempotent() {
        let diagnostics = RuntimeDiagnostics()

        diagnostics.codexProcessStarted(321)
        diagnostics.codexStdoutReaderStarted(processID: 321)
        diagnostics.codexProcessStopped(321)
        diagnostics.codexProcessStopped(321)
        diagnostics.codexStdoutReaderStopped(processID: 321)
        diagnostics.codexStdoutReaderStopped(processID: 321)

        let snapshot = diagnostics.snapshot()
        XCTAssertEqual(snapshot.codexConnectionState, "disconnected")
        XCTAssertTrue(snapshot.codexProcessIDs.isEmpty)
        XCTAssertEqual(snapshot.codexStdoutReaderCount, 0)
    }

    func testLogLineContainsOnlySanitizedScalarState() {
        let diagnostics = RuntimeDiagnostics()
        diagnostics.refreshStarted(at: Date(timeIntervalSince1970: 2_000_000_000))
        diagnostics.notificationsUpdated(pendingCount: 1, deduplicationEntryCount: 2)

        let line = diagnostics.snapshot().logLine(reason: "test")

        XCTAssertTrue(line.contains("runtime_snapshot reason=test"))
        XCTAssertTrue(line.contains("app_refresh_active=1"))
        XCTAssertTrue(line.contains("pending_notifications=1"))
        XCTAssertFalse(line.contains("token"))
        XCTAssertFalse(line.contains("prompt"))
        XCTAssertFalse(line.contains("/Users/"))
    }
}
#endif
