import AppKit
import CoreServices

enum ApplicationLaunchSource: Equatable, Sendable {
    case explicit
    case loginItem
}

enum MenuBarLaunchDisposition: Equatable, Sendable {
    case normal
    case recovery
    case quietExit
}

struct MenuBarRecoveryPolicy {
    static func disposition(
        isMenuBarItemRequested: Bool,
        launchSource: ApplicationLaunchSource
    ) -> MenuBarLaunchDisposition {
        guard !isMenuBarItemRequested else { return .normal }
        return launchSource == .loginItem ? .quietExit : .recovery
    }

    static func shouldPresentRecoveryOnReopen(isMenuBarItemVisible: Bool) -> Bool {
        !isMenuBarItemVisible
    }
}

@MainActor
enum ApplicationLaunchSourceDetector {
    static func current() -> ApplicationLaunchSource {
        source(for: NSAppleEventManager.shared().currentAppleEvent)
    }

    static func source(for event: NSAppleEventDescriptor?) -> ApplicationLaunchSource {
        guard
            let event,
            event.eventID == kAEOpenApplication,
            event.paramDescriptor(forKeyword: keyAELaunchedAsLogInItem) != nil
        else {
            return .explicit
        }
        return .loginItem
    }
}
