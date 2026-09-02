import AppKit
import CoreServices
import XCTest
@testable import QuotaPulse

final class MenuBarRecoveryPolicyTests: XCTestCase {
    func testRequestedExtraUsesNormalPathForExplicitLaunch() {
        XCTAssertEqual(
            MenuBarRecoveryPolicy.disposition(
                isMenuBarItemRequested: true,
                launchSource: .explicit
            ),
            .normal
        )
    }

    func testHiddenExtraUsesRecoveryPathForExplicitLaunch() {
        XCTAssertEqual(
            MenuBarRecoveryPolicy.disposition(
                isMenuBarItemRequested: false,
                launchSource: .explicit
            ),
            .recovery
        )
    }

    func testHiddenExtraExitsQuietlyForLoginItemLaunch() {
        XCTAssertEqual(
            MenuBarRecoveryPolicy.disposition(
                isMenuBarItemRequested: false,
                launchSource: .loginItem
            ),
            .quietExit
        )
    }

    func testRequestedExtraUsesNormalPathForLoginItemLaunch() {
        XCTAssertEqual(
            MenuBarRecoveryPolicy.disposition(
                isMenuBarItemRequested: true,
                launchSource: .loginItem
            ),
            .normal
        )
    }

    func testExplicitReopenPresentsRecoveryOnlyWhileRuntimeInsertionIsFalse() {
        XCTAssertTrue(
            MenuBarRecoveryPolicy.shouldPresentRecoveryOnReopen(
                isMenuBarItemVisible: false
            )
        )
        XCTAssertFalse(
            MenuBarRecoveryPolicy.shouldPresentRecoveryOnReopen(
                isMenuBarItemVisible: true
            )
        )
    }

    @MainActor
    func testLaunchSourceDetectorRecognizesPublicLoginItemMarker() {
        let event = makeOpenApplicationEvent()
        event.setParam(
            NSAppleEventDescriptor(boolean: true),
            forKeyword: keyAELaunchedAsLogInItem
        )

        XCTAssertEqual(ApplicationLaunchSourceDetector.source(for: event), .loginItem)
    }

    @MainActor
    func testLaunchSourceDetectorTreatsUnmarkedOpenEventAsExplicit() {
        XCTAssertEqual(
            ApplicationLaunchSourceDetector.source(for: makeOpenApplicationEvent()),
            .explicit
        )
    }

    private func makeOpenApplicationEvent() -> NSAppleEventDescriptor {
        NSAppleEventDescriptor(
            eventClass: kCoreEventClass,
            eventID: kAEOpenApplication,
            targetDescriptor: nil,
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID)
        )
    }
}
