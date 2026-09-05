import Foundation
import XCTest
@testable import QuotaMew

final class DashboardHeaderStatusTests: XCTestCase {
    func testActiveRefreshIsLoading() {
        XCTAssertEqual(
            DashboardHeaderStatus(
                isRefreshing: true,
                hasLoadingProvider: false,
                lastUpdatedAt: nil
            ),
            .loading
        )
    }

    func testInitialProviderStateIsLoadingBeforeRefreshStarts() {
        XCTAssertEqual(
            DashboardHeaderStatus(
                isRefreshing: false,
                hasLoadingProvider: true,
                lastUpdatedAt: nil
            ),
            .loading
        )
    }

    func testCompletedRefreshWithoutASnapshotIsUnavailable() {
        XCTAssertEqual(
            DashboardHeaderStatus(
                isRefreshing: false,
                hasLoadingProvider: false,
                lastUpdatedAt: nil
            ),
            .unavailable
        )
    }

    func testCompletedRefreshWithASnapshotShowsItsCaptureTime() {
        let capturedAt = Date(timeIntervalSince1970: 2_000_000_000)

        XCTAssertEqual(
            DashboardHeaderStatus(
                isRefreshing: false,
                hasLoadingProvider: false,
                lastUpdatedAt: capturedAt
            ),
            .updated(capturedAt)
        )
    }
}
