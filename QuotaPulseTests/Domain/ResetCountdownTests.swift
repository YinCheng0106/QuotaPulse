import XCTest
@testable import QuotaPulse

final class ResetCountdownTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000)
    private let english = Locale(identifier: "en")

    func testFormatsMinuteHourAndDayRanges() {
        XCTAssertEqual(
            ResetCountdown.text(until: now.addingTimeInterval(90), now: now, locale: english),
            "2 min"
        )
        XCTAssertEqual(
            ResetCountdown.text(
                until: now.addingTimeInterval(2 * 3_600 + 15 * 60),
                now: now,
                locale: english
            ),
            "2 hr, 15 min"
        )
        XCTAssertEqual(
            ResetCountdown.text(
                until: now.addingTimeInterval(2 * 86_400 + 4 * 3_600),
                now: now,
                locale: english
            ),
            "2 days, 4 hr"
        )
    }

    func testExpiredAndMissingResetTimesDoNotInferAReset() {
        XCTAssertEqual(
            ResetCountdown.text(until: now, now: now, locale: english),
            "Refresh needed"
        )
        XCTAssertEqual(
            ResetCountdown.text(until: nil, now: now, locale: english),
            "Reset time unavailable"
        )
    }

    func testRoundsAcrossHourBoundariesWithoutSixtyMinuteLabels() {
        XCTAssertEqual(
            ResetCountdown.text(
                until: now.addingTimeInterval(3_600),
                now: now,
                locale: english
            ),
            "1 hr"
        )
        XCTAssertEqual(
            ResetCountdown.text(
                until: now.addingTimeInterval(7_199),
                now: now,
                locale: english
            ),
            "2 hr"
        )
        XCTAssertEqual(
            ResetCountdown.text(
                until: now.addingTimeInterval(86_399),
                now: now,
                locale: english
            ),
            "1 day"
        )
    }

    func testFormatsTraditionalChineseDurationsAndUnavailableStates() {
        let traditionalChinese = Locale(identifier: "zh-Hant-TW")

        XCTAssertEqual(
            ResetCountdown.text(
                until: now.addingTimeInterval(2 * 3_600 + 15 * 60),
                now: now,
                locale: traditionalChinese
            ),
            "2小時15分鐘"
        )
        XCTAssertEqual(
            ResetCountdown.text(until: nil, now: now, locale: traditionalChinese),
            "無法取得重置時間"
        )
    }
}
