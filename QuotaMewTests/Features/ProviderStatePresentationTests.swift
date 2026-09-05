import XCTest
@testable import QuotaMew

final class ProviderStatePresentationTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)
    private let english = Locale(identifier: "en")

    func testAvailableProviderShowsAvailablePresentation() {
        let presentation = makePresentation(status: .available, snapshot: makeSnapshot())

        XCTAssertEqual(presentation.kind, .available)
        XCTAssertEqual(presentation.badgeLabel, "Available")
        XCTAssertFalse(presentation.showsStatusMessage)
    }

    func testLoadingProviderShowsRefreshingPresentationWhenUsageRemainsVisible() {
        let presentation = makePresentation(status: .loading, snapshot: makeSnapshot())

        XCTAssertEqual(presentation.kind, .loading)
        XCTAssertEqual(presentation.badgeLabel, "Refreshing")
        XCTAssertEqual(presentation.title, "Refreshing…")
        XCTAssertTrue(presentation.showsStatusMessage)
    }

    func testUnavailableUsageIsNotPresentedAsFatalError() {
        let presentation = makePresentation(status: .failed(.usageUnavailable))

        XCTAssertEqual(presentation.kind, .unavailable)
        XCTAssertEqual(presentation.title, "Usage data unavailable")
    }

    func testCodexRuntimeNotDetectedHasSpecificSafeMessage() {
        let presentation = makePresentation(status: .notInstalled)

        XCTAssertEqual(presentation.kind, .unavailable)
        XCTAssertEqual(presentation.badgeLabel, "Not detected")
        XCTAssertEqual(presentation.title, "Codex runtime not detected")
    }

    func testClaudeNotConfiguredIsExperimentalAndSpecific() {
        let presentation = makePresentation(providerID: .claude, status: .notConfigured)

        XCTAssertEqual(presentation.kind, .unavailable)
        XCTAssertEqual(presentation.badgeLabel, "Not configured")
        XCTAssertEqual(presentation.title, "Claude Code is not configured")
        XCTAssertEqual(presentation.supportLabel, "Experimental")
    }

    func testRefreshFailureWithoutCachedSnapshotShowsError() {
        let presentation = makePresentation(status: .failed(.refreshFailed))

        XCTAssertEqual(presentation.kind, .error)
        XCTAssertEqual(presentation.title, "Unable to refresh usage")
        XCTAssertEqual(presentation.detail, "Previously fetched usage is not available.")
    }

    func testRefreshFailureWithCachedSnapshotShowsStaleUsage() {
        let presentation = makePresentation(
            status: .failed(.refreshFailed),
            snapshot: makeSnapshot()
        )

        XCTAssertEqual(presentation.kind, .stale)
        XCTAssertEqual(presentation.badgeLabel, "Stale")
        XCTAssertEqual(presentation.title, "Showing previously fetched usage")
        XCTAssertEqual(presentation.detail, "Unable to refresh usage")
    }

    func testMissingResetTimestampRemainsAvailableAndUsesUnavailableCountdown() {
        let snapshot = makeSnapshot(resetAt: nil)
        let presentation = makePresentation(status: .available, snapshot: snapshot)

        XCTAssertEqual(presentation.kind, .available)
        XCTAssertEqual(
            ResetCountdown.text(
                until: snapshot.windows[0].resetAt,
                now: now,
                locale: english
            ),
            "Reset time unavailable"
        )
    }

    func testOldSnapshotIsPresentedAsStale() {
        let snapshot = makeSnapshot(capturedAt: now.addingTimeInterval(-901))
        let presentation = makePresentation(status: .available, snapshot: snapshot)

        XCTAssertEqual(presentation.kind, .stale)
        XCTAssertEqual(presentation.title, "Usage may be out of date")
        XCTAssertTrue(presentation.showsStatusMessage)
    }

    func testFailurePresentationDoesNotExposeInternalDiagnosticDetails() {
        let presentation = makePresentation(status: .failed(.runtimeLaunchFailed))
        let visibleText = [presentation.title, presentation.detail].compactMap { $0 }.joined()

        XCTAssertEqual(presentation.title, "Unable to start Codex runtime")
        XCTAssertFalse(visibleText.contains("runtimeLaunchFailed"))
        XCTAssertFalse(visibleText.contains("NSError"))
        XCTAssertFalse(visibleText.contains("/Users/"))
    }

    func testTraditionalChineseProviderStatusPresentation() {
        let presentation = ProviderStatePresentation(
            state: ProviderState(
                providerID: .claude,
                status: .notConfigured,
                snapshot: nil
            ),
            now: now,
            locale: Locale(identifier: "zh-Hant-TW")
        )

        XCTAssertEqual(presentation.badgeLabel, "尚未設定")
        XCTAssertEqual(presentation.title, "Claude Code 尚未設定")
        XCTAssertEqual(presentation.supportLabel, "實驗性功能")
    }

    private func makePresentation(
        providerID: ProviderID = .codex,
        status: ProviderStatus,
        snapshot: ProviderUsageSnapshot? = nil
    ) -> ProviderStatePresentation {
        ProviderStatePresentation(
            state: ProviderState(
                providerID: providerID,
                status: status,
                snapshot: snapshot
            ),
            now: now,
            locale: english
        )
    }

    private func makeSnapshot(
        capturedAt: Date? = nil,
        resetAt: Date? = Date(timeIntervalSince1970: 2_000_003_600)
    ) -> ProviderUsageSnapshot {
        ProviderUsageSnapshot(
            providerID: .codex,
            windows: [
                UsageWindow(
                    id: "codex.primary",
                    label: "Primary window",
                    usedPercentage: 42,
                    resetAt: resetAt,
                    duration: .seconds(18_000)
                )
            ],
            capturedAt: capturedAt ?? now,
            source: UsageSource(kind: .mock, label: "Test", documentationURL: nil)
        )
    }
}
