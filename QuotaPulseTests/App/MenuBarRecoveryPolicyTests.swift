import AppKit
import CoreServices
import XCTest
@testable import QuotaPulse

final class MenuBarRecoveryPolicyTests: XCTestCase {
    func testRequestedExtraUsesNormalPathForExplicitLaunch() {
        XCTAssertEqual(
            MenuBarRecoveryPolicy.disposition(
                isMenuBarExtraRequested: true,
                launchSource: .explicit
            ),
            .normal
        )
    }

    func testHiddenExtraUsesRecoveryPathForExplicitLaunch() {
        XCTAssertEqual(
            MenuBarRecoveryPolicy.disposition(
                isMenuBarExtraRequested: false,
                launchSource: .explicit
            ),
            .recovery
        )
    }

    func testHiddenExtraExitsQuietlyForLoginItemLaunch() {
        XCTAssertEqual(
            MenuBarRecoveryPolicy.disposition(
                isMenuBarExtraRequested: false,
                launchSource: .loginItem
            ),
            .quietExit
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
