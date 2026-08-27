import ServiceManagement

enum LaunchAtLoginStatus: Equatable, Sendable {
    case enabled
    case disabled
    case requiresApproval
    case unavailable
}

@MainActor
protocol LaunchAtLoginControlling: AnyObject {
    var status: LaunchAtLoginStatus { get }
    func refreshStatus()
    func setEnabled(_ enabled: Bool) throws
}

@MainActor
final class LaunchAtLoginController: LaunchAtLoginControlling {
    private let service: SMAppService

    init(service: SMAppService = .mainApp) {
        self.service = service
    }

    var status: LaunchAtLoginStatus {
        Self.map(service.status)
    }

    static func map(_ status: SMAppService.Status) -> LaunchAtLoginStatus {
        switch status {
        case .enabled: .enabled
        case .notRegistered: .disabled
        case .requiresApproval: .requiresApproval
        case .notFound: .unavailable
        @unknown default: .unavailable
        }
    }

    func refreshStatus() {
        // SMAppService.status remains the system source of truth and is read on demand.
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try service.register()
        } else {
            try service.unregister()
        }
    }
}
