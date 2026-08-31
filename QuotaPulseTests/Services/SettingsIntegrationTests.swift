import Foundation
import ServiceManagement
import XCTest
@testable import QuotaPulse

@MainActor
final class SettingsIntegrationTests: XCTestCase {
    func testCodexDisabledSkipsOnlyCodexWork() async {
        let (store, defaults, suiteName) = makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let codex = SettingsCountingProvider(id: .codex)
        let claude = SettingsCountingProvider(id: .claude)
        store.setProvider(.codex, enabled: false)
        let service = UsageService(providers: [codex, claude], preferences: store)

        let states = await service.refresh()

        XCTAssertEqual(states.map(\.status), [.disabled, .available])
        let codexFetchCount = await codex.fetchCount
        let claudeFetchCount = await claude.fetchCount
        XCTAssertEqual(codexFetchCount, 0)
        XCTAssertEqual(claudeFetchCount, 1)
    }

    func testDisabledProviderIsSkippedDuringStartupRefresh() async {
        let (store, defaults, suiteName) = makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        store.setProvider(.codex, enabled: false)
        let codex = SettingsCountingProvider(id: .codex)
        let claude = SettingsCountingProvider(id: .claude)
        let providers: [any UsageProvider] = [codex, claude]
        let model = AppModel(
            providerIDs: providers.map(\.id),
            enabledProviderIDs: [.claude],
            refreshCoordinator: RefreshCoordinator(
                usageService: UsageService(providers: providers, preferences: store)
            ),
            notificationService: SettingsNotificationService(),
            observesLifecycle: false
        )

        model.start()
        await waitUntilRefreshFinishes(model)

        let codexFetchCount = await codex.fetchCount
        let claudeFetchCount = await claude.fetchCount
        XCTAssertEqual(codexFetchCount, 0)
        XCTAssertEqual(claudeFetchCount, 1)
        XCTAssertEqual(model.activeProviderStates.map(\.providerID), [.claude])
    }

    func testManualRefreshFetchesEveryEnabledProviderAndSkipsDisabledProvider() async {
        let (store, defaults, suiteName) = makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        store.setProvider(.claude, enabled: false)
        let codex = SettingsCountingProvider(id: .codex)
        let claude = SettingsCountingProvider(id: .claude)
        let service = UsageService(providers: [codex, claude], preferences: store)

        _ = await service.refresh()
        _ = await service.refresh()

        let codexFetchCount = await codex.fetchCount
        let claudeFetchCount = await claude.fetchCount
        XCTAssertEqual(codexFetchCount, 2)
        XCTAssertEqual(claudeFetchCount, 0)
    }

    func testReenablingCodexRestoresWorkWithoutAffectingClaude() async {
        let (store, defaults, suiteName) = makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let codex = SettingsCountingProvider(id: .codex)
        let claude = SettingsCountingProvider(id: .claude)
        let service = UsageService(providers: [codex, claude], preferences: store)
        store.setProvider(.codex, enabled: false)
        _ = await service.refresh()

        store.setProvider(.codex, enabled: true)
        let states = await service.refresh()

        XCTAssertEqual(states.map(\.status), [.available, .available])
        let codexFetchCount = await codex.fetchCount
        let claudeFetchCount = await claude.fetchCount
        XCTAssertEqual(codexFetchCount, 1)
        XCTAssertEqual(claudeFetchCount, 2)
    }

    func testSettingsReenableRefreshesProviderWithoutRestart() async {
        let (store, defaults, suiteName) = makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        store.setProvider(.codex, enabled: false)
        let codex = SettingsCountingProvider(id: .codex)
        let providers: [any UsageProvider] = [codex]
        let notifications = SettingsNotificationService()
        let appModel = AppModel(
            providerIDs: [.codex],
            enabledProviderIDs: [],
            refreshCoordinator: RefreshCoordinator(
                usageService: UsageService(providers: providers, preferences: store)
            ),
            notificationService: notifications,
            observesLifecycle: false
        )
        let settingsModel = SettingsModel(
            store: store,
            appModel: appModel,
            notificationService: notifications,
            launchAtLoginController: SettingsLaunchAtLoginController(status: .disabled)
        )

        let transitionResult: Void = settingsModel.setProvider(.codex, enabled: true)
        XCTAssertTrue(store.isCodexEnabled)
        XCTAssertEqual(appModel.activeProviderStates.map(\.providerID), [.codex])
        _ = transitionResult
        await appModel.refresh()

        let codexFetchCount = await codex.fetchCount
        XCTAssertEqual(codexFetchCount, 1)
        XCTAssertEqual(appModel.activeProviderStates.map(\.providerID), [.codex])
        XCTAssertEqual(appModel.activeProviderStates.first?.status, .available)
    }

    func testProviderTransitionAPIRequiresNoTaskFromSettingsView() {
        let (store, defaults, suiteName) = makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let notifications = SettingsNotificationService()
        let model = SettingsModel(
            store: store,
            appModel: AppModel(
                providerIDs: [.codex],
                refreshCoordinator: RefreshCoordinator(
                    usageService: UsageService(providers: [])
                ),
                notificationService: notifications,
                observesLifecycle: false
            ),
            notificationService: notifications,
            launchAtLoginController: SettingsLaunchAtLoginController(status: .disabled)
        )

        let result: Void = model.setProvider(.codex, enabled: false)

        _ = result
        XCTAssertFalse(store.isCodexEnabled)
        XCTAssertEqual(notifications.providerTransitions, [.codex: false])
    }

    func testLaunchAtLoginUsesControllerStateAfterSuccessAndFailure() async {
        let (store, defaults, suiteName) = makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let appModel = makeAppModel()
        let notifications = SettingsNotificationService()
        let launchController = SettingsLaunchAtLoginController(status: .disabled)
        let model = SettingsModel(
            store: store,
            appModel: appModel,
            notificationService: notifications,
            launchAtLoginController: launchController
        )

        model.setLaunchAtLoginEnabled(true)
        XCTAssertEqual(model.launchAtLoginStatus, .enabled)
        XCTAssertFalse(model.launchAtLoginUpdateFailed)

        launchController.shouldFail = true
        model.setLaunchAtLoginEnabled(false)
        XCTAssertEqual(model.launchAtLoginStatus, .enabled)
        XCTAssertTrue(model.launchAtLoginUpdateFailed)
    }

    func testMenuBarRecoveryActionRequestsInsertion() {
        let (store, defaults, suiteName) = makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        store.setMenuBarExtraRequested(false)
        let model = SettingsModel(
            store: store,
            appModel: makeAppModel(),
            notificationService: SettingsNotificationService(),
            launchAtLoginController: SettingsLaunchAtLoginController(status: .disabled)
        )

        model.setMenuBarExtraRequested(true)

        XCTAssertTrue(store.isMenuBarExtraRequested)
        XCTAssertTrue(model.isMenuBarExtraInserted)
    }

    func testRuntimeMenuBarRemovalDoesNotRewritePersistedUserIntent() {
        let (store, defaults, suiteName) = makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = SettingsModel(
            store: store,
            appModel: makeAppModel(),
            notificationService: SettingsNotificationService(),
            launchAtLoginController: SettingsLaunchAtLoginController(status: .disabled)
        )

        model.menuBarExtraInsertionDidChange(false)

        XCTAssertFalse(model.isMenuBarExtraInserted)
        XCTAssertTrue(store.isMenuBarExtraRequested)
    }

    func testExplicitMenuBarHidePersistsUserIntentAndRuntimeState() {
        let (store, defaults, suiteName) = makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = SettingsModel(
            store: store,
            appModel: makeAppModel(),
            notificationService: SettingsNotificationService(),
            launchAtLoginController: SettingsLaunchAtLoginController(status: .disabled)
        )

        model.setMenuBarExtraRequested(false)

        XCTAssertFalse(model.isMenuBarExtraInserted)
        XCTAssertFalse(store.isMenuBarExtraRequested)
    }

    func testLaunchAtLoginMapsEveryKnownSystemStatus() {
        XCTAssertEqual(LaunchAtLoginController.map(.enabled), .enabled)
        XCTAssertEqual(LaunchAtLoginController.map(.notRegistered), .disabled)
        XCTAssertEqual(LaunchAtLoginController.map(.requiresApproval), .requiresApproval)
        XCTAssertEqual(LaunchAtLoginController.map(.notFound), .unavailable)
    }

    func testLaunchAtLoginCanRegisterWhenServiceIsNotFound() {
        let (store, defaults, suiteName) = makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let launchController = SettingsLaunchAtLoginController(status: .unavailable)
        let model = SettingsModel(
            store: store,
            appModel: makeAppModel(),
            notificationService: SettingsNotificationService(),
            launchAtLoginController: launchController
        )

        model.setLaunchAtLoginEnabled(true)

        XCTAssertEqual(model.launchAtLoginStatus, .enabled)
        XCTAssertFalse(model.launchAtLoginUpdateFailed)
    }

    func testCopyDiagnosticsWritesEnglishPrivacySafeReport() async {
        let (store, defaults, suiteName) = makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let clipboard = SettingsDiagnosticClipboard()
        let model = SettingsModel(
            store: store,
            appModel: makeAppModel(),
            notificationService: SettingsNotificationService(),
            launchAtLoginController: SettingsLaunchAtLoginController(status: .disabled),
            diagnosticClipboard: clipboard
        )

        await model.copyDiagnostics()

        XCTAssertEqual(clipboard.writeCount, 1)
        XCTAssertTrue(clipboard.text?.contains("QuotaPulse Diagnostics") == true)
        XCTAssertTrue(clipboard.text?.contains("Privacy:") == true)
        XCTAssertEqual(
            model.diagnosticsCopyFeedback,
            AppLocalization.string("Diagnostics copied.")
        )
    }

    private func makeStore() -> (SettingsStore, UserDefaults, String) {
        let suiteName = "dev.quotapulse.tests.settings.integration.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return (SettingsStore(defaults: defaults), defaults, suiteName)
    }

    private func makeAppModel() -> AppModel {
        AppModel(
            providerIDs: [],
            refreshCoordinator: RefreshCoordinator(
                usageService: UsageService(providers: [])
            ),
            notificationService: SettingsNotificationService(),
            observesLifecycle: false
        )
    }

    private func waitUntilRefreshFinishes(_ model: AppModel) async {
        while model.isRefreshing {
            await Task.yield()
        }
    }
}

@MainActor
private final class SettingsDiagnosticClipboard: DiagnosticClipboardWriting {
    private(set) var writeCount = 0
    private(set) var text: String?

    func write(_ text: String) -> Bool {
        writeCount += 1
        self.text = text
        return true
    }
}

private actor SettingsCountingProvider: UsageProvider {
    nonisolated let id: ProviderID
    private(set) var fetchCount = 0

    init(id: ProviderID) {
        self.id = id
    }

    func fetchUsage() async throws -> ProviderUsageSnapshot {
        fetchCount += 1
        return ProviderUsageSnapshot(
            providerID: id,
            windows: [],
            capturedAt: Date(timeIntervalSince1970: 2_000_000_000),
            source: UsageSource(kind: .mock, label: "Test", documentationURL: nil)
        )
    }
}

@MainActor
private final class SettingsNotificationService: NotificationServicing {
    private(set) var providerTransitions: [ProviderID: Bool] = [:]

    func evaluate(_ providerStates: [ProviderState], now: Date) async {}
    func authorizationStatus() async -> NotificationAuthorizationStatus { .authorized }
    func providerEnablementDidChange(_ providerID: ProviderID, isEnabled: Bool) {
        providerTransitions[providerID] = isEnabled
    }
    #if DEBUG
    func sendTestNotification() async throws {}
    #endif
}

private enum SettingsLaunchAtLoginError: Error {
    case failed
}

@MainActor
private final class SettingsLaunchAtLoginController: LaunchAtLoginControlling {
    var status: LaunchAtLoginStatus
    var shouldFail = false

    init(status: LaunchAtLoginStatus) {
        self.status = status
    }

    func refreshStatus() {}

    func setEnabled(_ enabled: Bool) throws {
        guard !shouldFail else { throw SettingsLaunchAtLoginError.failed }
        status = enabled ? .enabled : .disabled
    }
}
