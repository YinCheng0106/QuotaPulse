import XCTest
@testable import QuotaPulse

final class UsageWindowTests: XCTestCase {
    func testRemainingPercentageUsesClampedUsage() {
        let overLimit = makeWindow(usedPercentage: 140)
        let underLimit = makeWindow(usedPercentage: -20)

        XCTAssertEqual(overLimit.displayUsedPercentage, 100)
        XCTAssertEqual(overLimit.remainingPercentage, 0)
        XCTAssertEqual(underLimit.displayUsedPercentage, 0)
        XCTAssertEqual(underLimit.remainingPercentage, 100)
    }

    func testNonFiniteUsageRemainsUnavailable() {
        let window = makeWindow(usedPercentage: .infinity)

        XCTAssertNil(window.displayUsedPercentage)
        XCTAssertNil(window.remainingPercentage)
        XCTAssertNil(window.progress)
    }

    func testMissingUsageRemainsUnavailable() {
        let window = UsageWindow(
            id: "test",
            label: "Test",
            usedPercentage: nil,
            resetAt: Date(timeIntervalSince1970: 2_000_000_000),
            duration: nil
        )

        XCTAssertNil(window.displayUsedPercentage)
        XCTAssertNil(window.remainingPercentage)
        XCTAssertNil(window.progress)
    }

    private func makeWindow(usedPercentage: Double) -> UsageWindow {
        UsageWindow(
            id: "test",
            label: "Test",
            usedPercentage: usedPercentage,
            resetAt: nil,
            duration: nil
        )
    }
}
