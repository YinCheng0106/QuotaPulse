import Observation

@Observable
@MainActor
final class SettingsModel {
    let store: SettingsStore

    private(set) var launchAtLoginStatus: LaunchAtLoginStatus = .disabled
    private(set) var notificationAuthorizationStatus: NotificationAuthorizationStatus = .notDetermined
    private(set) var isUpdatingLaunchAtLogin = false
    private(set) var launchAtLoginUpdateFailed = false

    private let appModel: AppModel
    private let notificationService: any NotificationServicing
    private let launchAtLoginController: any LaunchAtLoginControlling

    init(
        store: SettingsStore,
        appModel: AppModel,
        notificationService: any NotificationServicing,
        launchAtLoginController: any LaunchAtLoginControlling = LaunchAtLoginController()
    ) {
        self.store = store
        self.appModel = appModel
        self.notificationService = notificationService
        self.launchAtLoginController = launchAtLoginController
        refreshLaunchAtLoginStatus()
    }

    func refreshSystemState() async {
        refreshLaunchAtLoginStatus()
        notificationAuthorizationStatus = await notificationService.authorizationStatus()
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
