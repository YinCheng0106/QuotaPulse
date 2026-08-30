import AppKit
import Observation

@MainActor
protocol DiagnosticClipboardWriting: AnyObject {
    func write(_ text: String) -> Bool
}

@MainActor
private final class SystemDiagnosticClipboard: DiagnosticClipboardWriting {
    func write(_ text: String) -> Bool {
        NSPasteboard.general.clearContents()
        return NSPasteboard.general.setString(text, forType: .string)
    }
}

@Observable
@MainActor
final class SettingsModel {
    let store: SettingsStore

    private(set) var launchAtLoginStatus: LaunchAtLoginStatus = .disabled
    private(set) var notificationAuthorizationStatus: NotificationAuthorizationStatus = .notDetermined
    private(set) var diagnostics: CompatibilityDiagnosticsSnapshot?
    private(set) var diagnosticsCopyFeedback: String?
    private(set) var isUpdatingLaunchAtLogin = false
    private(set) var launchAtLoginUpdateFailed = false

    private let appModel: AppModel
    private let notificationService: any NotificationServicing
    private let launchAtLoginController: any LaunchAtLoginControlling
    private let diagnosticClipboard: any DiagnosticClipboardWriting

    init(
        store: SettingsStore,
        appModel: AppModel,
        notificationService: any NotificationServicing,
        launchAtLoginController: any LaunchAtLoginControlling = LaunchAtLoginController(),
        diagnosticClipboard: any DiagnosticClipboardWriting = SystemDiagnosticClipboard()
    ) {
        self.store = store
        self.appModel = appModel
        self.notificationService = notificationService
        self.launchAtLoginController = launchAtLoginController
        self.diagnosticClipboard = diagnosticClipboard
        refreshLaunchAtLoginStatus()
    }

    func refreshSystemState() async {
        refreshLaunchAtLoginStatus()
        notificationAuthorizationStatus = await notificationService.authorizationStatus()
    }

    func refreshDiagnostics() async {
        diagnostics = await appModel.compatibilityDiagnostics()
    }

    func copyDiagnostics() async {
        let snapshot = await appModel.compatibilityDiagnostics()
        diagnostics = snapshot
        let didCopy = diagnosticClipboard.write(
            CompatibilityDiagnosticsReport.make(from: snapshot)
        )
        diagnosticsCopyFeedback = AppLocalization.string(
            didCopy ? "Diagnostics copied." : "Diagnostics could not be copied."
        )
    }

    func setLaunchAtLoginEnabled(_ enabled: Bool) {
        guard !isUpdatingLaunchAtLogin else { return }
        isUpdatingLaunchAtLogin = true
        launchAtLoginUpdateFailed = false
        defer {
            refreshLaunchAtLoginStatus()
            isUpdatingLaunchAtLogin = false
        }

        do {
            try launchAtLoginController.setEnabled(enabled)
        } catch {
            launchAtLoginUpdateFailed = true
        }
    }

    func setProvider(_ providerID: ProviderID, enabled: Bool) {
        guard store.isProviderEnabled(providerID) != enabled else { return }
        store.setProvider(providerID, enabled: enabled)
        appModel.providerPreferencesDidChange()
    }

    func setNotificationsEnabled(_ enabled: Bool) async {
        guard store.areNotificationsEnabled != enabled else { return }
        store.setNotificationsEnabled(enabled)
        await notificationService.preferencesDidChange()
        notificationAuthorizationStatus = await notificationService.authorizationStatus()
    }

    func setReminder(
        windowClass: NotificationWindowClass,
        minutes: Int,
        enabled: Bool
    ) async {
        let before = store.notificationPreferences
        store.setReminder(windowClass: windowClass, minutes: minutes, enabled: enabled)
        guard store.notificationPreferences != before else { return }
        await notificationService.preferencesDidChange()
    }

    private func refreshLaunchAtLoginStatus() {
        launchAtLoginController.refreshStatus()
        launchAtLoginStatus = launchAtLoginController.status
    }
}
