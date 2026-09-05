import Foundation
import XCTest
@testable import QuotaMew

final class UsagePresentationTests: XCTestCase {
    private let english = Locale(identifier: "en")

    func testRemainingIsTheDefaultPresentationSemantic() {
        let presentation = UsagePresentation(window: makeWindow(used: 39), mode: .remaining)

        XCTAssertEqual(presentation.percentage, 61)
        XCTAssertEqual(presentation.text(locale: english), "61% remaining")
    }

    func testUsedPresentationDerivesFromTheSameNormalizedWindow() {
        let window = makeWindow(used: 39)
        let presentation = UsagePresentation(window: window, mode: .used)

        XCTAssertEqual(presentation.percentage, 39)
        XCTAssertEqual(presentation.text(locale: english), "39% used")
        XCTAssertEqual(window.usedPercentage, 39)
        XCTAssertEqual(window.remainingPercentage, 61)
    }

    func testCompactMenuBarTextIsOnlyOneRoundedIntegerPercentage() {
        let remaining = UsagePresentation(window: makeWindow(used: 39.4), mode: .remaining)
        let used = UsagePresentation(window: makeWindow(used: 39.4), mode: .used)

        XCTAssertEqual(remaining.compactText(locale: english), "61%")
        XCTAssertEqual(used.compactText(locale: english), "39%")
    }

    func testCompactMenuBarTextIsNilWithoutRenderableUsage() {
        let window = UsageWindow(
            id: "primary",
            label: "Primary window",
            usedPercentage: nil,
            resetAt: nil,
            duration: nil
        )

        XCTAssertNil(UsagePresentation(window: window, mode: .remaining).compactText(locale: english))
        XCTAssertNil(UsagePresentation(window: window, mode: .used).compactText(locale: english))
    }

    func testPresentationDoesNotChangeResetEvidenceInputs() {
        let window = makeWindow(used: 82)
        let remaining = UsagePresentation(window: window, mode: .remaining)
        let used = UsagePresentation(window: window, mode: .used)

        XCTAssertEqual(window.usedPercentage, 82)
        XCTAssertEqual(window.resetAt, Date(timeIntervalSince1970: 2_000_003_600))
        XCTAssertEqual(remaining.percentage, 18)
        XCTAssertEqual(used.percentage, 82)
    }

    func testMenuBarExplicitPinNeverFallsBackWhenUnavailable() {
        let presentation = MenuBarPresentation(
            providerStates: [
                state(.codex, status: .available, used: 39),
                state(.claude, status: .notConfigured, used: nil),
            ],
            persistedPinnedProviderRawValue: ProviderID.claude.rawValue,
            mode: .remaining
        )

        XCTAssertEqual(presentation.persistedPinnedProvider, .claude)
        XCTAssertEqual(presentation.selectedProvider, .claude)
        XCTAssertNil(presentation.currentlyRenderedProvider)
        XCTAssertNil(presentation.usage)
        XCTAssertEqual(presentation.availability, .unavailable)
    }

    func testDisabledPinnedProviderRemainsPersistedAndBecomesRenderableAfterEnablement() {
        let disabled = MenuBarPresentation(
            providerStates: [state(.codex, status: .disabled, used: 39)],
            persistedPinnedProviderRawValue: ProviderID.codex.rawValue,
            mode: .remaining
        )
        let reenabled = MenuBarPresentation(
            providerStates: [state(.codex, status: .available, used: 39)],
            persistedPinnedProviderRawValue: ProviderID.codex.rawValue,
            mode: .remaining
        )

        XCTAssertEqual(disabled.persistedPinnedProvider, .codex)
        XCTAssertEqual(disabled.selectedProvider, .codex)
        XCTAssertNil(disabled.currentlyRenderedProvider)
        XCTAssertEqual(disabled.availability, .disabled)
        XCTAssertEqual(reenabled.currentlyRenderedProvider, .codex)
        XCTAssertEqual(reenabled.usage?.percentage, 61)
        XCTAssertEqual(reenabled.availability, .renderable)
    }

    func testUnknownPersistedPinIsSafeAndDoesNotBecomeAutomatic() {
        let presentation = MenuBarPresentation(
            providerStates: [state(.codex, status: .available, used: 39)],
            persistedPinnedProviderRawValue: "future-provider",
            mode: .remaining
        )

        XCTAssertNil(presentation.persistedPinnedProvider)
        XCTAssertNil(presentation.selectedProvider)
        XCTAssertNil(presentation.currentlyRenderedProvider)
        XCTAssertNil(presentation.usage)
        XCTAssertEqual(presentation.availability, .unavailable)
    }

    func testNoPinUsesFirstRenderableProviderInExistingOrder() {
        let presentation = MenuBarPresentation(
            providerStates: [
                state(.claude, status: .notConfigured, used: nil),
                state(.codex, status: .available, used: 39),
            ],
            persistedPinnedProviderRawValue: nil,
            mode: .used
        )

        XCTAssertEqual(presentation.currentlyRenderedProvider, .codex)
        XCTAssertEqual(presentation.usage?.percentage, 39)
        XCTAssertEqual(presentation.availability, .renderable)
    }

    func testAllDisabledStateHasNoRenderedProvider() {
        let presentation = MenuBarPresentation(
            providerStates: [
                state(.codex, status: .disabled, used: 39),
                state(.claude, status: .disabled, used: 61),
            ],
            persistedPinnedProviderRawValue: nil,
            mode: .remaining
        )

        XCTAssertNil(presentation.currentlyRenderedProvider)
        XCTAssertNil(presentation.usage)
        XCTAssertEqual(presentation.availability, .empty)
    }

    private func makeWindow(used: Double) -> UsageWindow {
        UsageWindow(
            id: "primary",
            label: "Primary window",
            usedPercentage: used,
            resetAt: Date(timeIntervalSince1970: 2_000_003_600),
            duration: .seconds(18_000)
        )
    }

    private func state(_ providerID: ProviderID, status: ProviderStatus, used: Double?) -> ProviderState {
        ProviderState(
            providerID: providerID,
            status: status,
            snapshot: used.map {
                ProviderUsageSnapshot(
                    providerID: providerID,
                    windows: [makeWindow(used: $0)],
                    capturedAt: Date(timeIntervalSince1970: 2_000_000_000),
                    source: UsageSource(kind: .mock, label: "Test", documentationURL: nil)
                )
            }
        )
    }
}
