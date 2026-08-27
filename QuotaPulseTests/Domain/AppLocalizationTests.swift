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

    func testUnsupportedSimplifiedChineseFallsBackToEnglish() {
        XCTAssertEqual(
            AppLocalization.string("Settings", locale: Locale(identifier: "zh-Hans-CN")),
            "Settings"
        )
    }
}
