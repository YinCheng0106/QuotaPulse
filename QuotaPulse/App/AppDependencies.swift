import Foundation

enum AppRuntimeEnvironment {
    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    static var shouldInsertMenuBarExtraOnLaunch: Bool {
        !isRunningTests
    }
}

@MainActor
enum AppDependencies {
    struct Runtime {
        let appModel: AppModel
        let settingsModel: SettingsModel
    }

    static func makeLiveProviders() -> [any UsageProvider] {
        [CodexProvider(), ClaudeProvider()]
    }

    static func makeAppModel(
        providers: [any UsageProvider] = makeLiveProviders(),
        preferences: SettingsStore? = nil,
        notificationService: (any NotificationServicing)? = nil
    ) -> AppModel {
        let usageService = UsageService(providers: providers, preferences: preferences)
        let refreshCoordinator = RefreshCoordinator(usageService: usageService)
        let runsAutomatically = !AppRuntimeEnvironment.isRunningTests

        let model = AppModel(
            providerIDs: providers.map(\.id),
            refreshCoordinator: refreshCoordinator,
            notificationService: notificationService ?? NotificationService(preferences: preferences),
            observesLifecycle: runsAutomatically
        )
        if runsAutomatically {
            model.start()
        }
        return model
    }

    static func makeRuntime() -> Runtime {
        let providers = makeLiveProviders()
        let settingsStore = SettingsStore()
        let notificationService = NotificationService(preferences: settingsStore)
        let appModel = makeAppModel(
            providers: providers,
            preferences: settingsStore,
            notificationService: notificationService
        )
        return Runtime(
            appModel: appModel,
            settingsModel: SettingsModel(
                store: settingsStore,
                appModel: appModel,
                notificationService: notificationService
            )
        )
    }

    static func makePreviewModel(now: Date = .now) -> AppModel {
        let providers: [any UsageProvider] = [
            MockUsageProvider.codex(now: now),
            MockUsageProvider.claude(now: now),
        ]
        let usageService = UsageService(providers: providers)
        let refreshCoordinator = RefreshCoordinator(usageService: usageService)

        return AppModel(
            providerIDs: providers.map(\.id),
            refreshCoordinator: refreshCoordinator,
            notificationService: PreviewNotificationService(),
            observesLifecycle: false
        )
    }
}

@MainActor
private final class PreviewNotificationService: NotificationServicing {
    func evaluate(_ providerStates: [ProviderState], now: Date) async {}

    #if DEBUG
    func sendTestNotification() async throws {}
    #endif
}
