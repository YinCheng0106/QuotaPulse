import Foundation
import XCTest
@testable import QuotaPulse

final class AppLocalizationTests: XCTestCase {
    func testDynamicPercentageFormattingInSupportedLanguages() {
        for percentage in [0, 1, 61, 100] {
            XCTAssertEqual(
                AppLocalization.usedPercentage(percentage, locale: Locale(identifier: "en")),
                "\(percentage)% used"
            )
            XCTAssertEqual(
                AppLocalization.remainingPercentage(percentage, locale: Locale(identifier: "en")),
                "\(percentage)% remaining"
            )
            XCTAssertEqual(
                AppLocalization.usedPercentage(
                    percentage,
                    locale: Locale(identifier: "zh-Hant-TW")
                ),
                "已使用 \(percentage)%"
            )
            XCTAssertEqual(
                AppLocalization.remainingPercentage(
                    percentage,
                    locale: Locale(identifier: "zh-Hant-TW")
                ),
                "剩餘 \(percentage)%"
            )
        }
    }

    func testNotificationPercentageFormattingInSupportedLanguages() {
        for percentage in [0, 1, 61, 100] {
            XCTAssertEqual(
                AppLocalization.notificationRemainingBody(
                    percentage,
                    locale: Locale(identifier: "en")
                ),
                "You still have \(percentage)% of your quota remaining."
            )
            XCTAssertEqual(
                AppLocalization.notificationRemainingBody(
                    percentage,
                    locale: Locale(identifier: "zh-Hant-TW")
                ),
                "你還有 \(percentage)% 的配額尚未使用。"
            )
        }
    }

    func testThresholdLabelsInSupportedLanguages() {
        XCTAssertEqual(
            AppLocalization.thresholdLabel(minutes: 30, locale: Locale(identifier: "en")),
            "30 minutes"
        )
        XCTAssertEqual(
            AppLocalization.thresholdLabel(minutes: 60, locale: Locale(identifier: "en")),
            "1 hour"
        )
        XCTAssertEqual(
            AppLocalization.thresholdLabel(
                minutes: 24 * 60,
                locale: Locale(identifier: "zh-Hant-TW")
            ),
            "24 小時"
        )
    }

    func testCompletedResetNotificationUsesLocalizedProviderAndWindowData() {
        XCTAssertEqual(
            AppLocalization.resetCompletedTitle(
                providerName: "Codex",
                locale: Locale(identifier: "en")
            ),
            "Codex quota reset"
        )
        XCTAssertEqual(
            AppLocalization.resetCompletedBody(
                windowLabel: "Primary window",
                duration: .seconds(5 * 60 * 60),
                locale: Locale(identifier: "en")
            ),
            "Your 5-hour usage window has refreshed."
        )
        XCTAssertEqual(
            AppLocalization.resetCompletedBody(
                windowLabel: "主要配額週期",
                duration: .seconds(7 * 24 * 60 * 60),
                locale: Locale(identifier: "zh-Hant-TW")
            ),
            "你的「7 天配額週期」已重新整理。"
        )
    }

    func testUnsupportedSimplifiedChineseFallsBackToEnglish() {
        XCTAssertEqual(
            AppLocalization.string("Settings", locale: Locale(identifier: "zh-Hans-CN")),
            "Settings"
        )
    }

    func testDiagnosticsUIUsesSupportedLanguages() {
        XCTAssertEqual(
            AppLocalization.string("Diagnostics", locale: Locale(identifier: "en")),
            "Diagnostics"
        )
        XCTAssertEqual(
            AppLocalization.string(
                "Diagnostics",
                locale: Locale(identifier: "zh-Hant-TW")
            ),
            "診斷"
        )
        XCTAssertEqual(
            AppLocalization.string(
                "App Server connection failed",
                locale: Locale(identifier: "zh-Hant-TW")
            ),
            "App Server 連線失敗"
        )
        XCTAssertEqual(
            AppLocalization.string(
                "Diagnostics copied.",
                locale: Locale(identifier: "zh-Hant-TW")
            ),
            "已複製診斷資訊。"
        )
    }
}
