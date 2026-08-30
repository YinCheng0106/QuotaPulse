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
    func evaluate(_ providerStates: [ProviderState], now: Date) async {}
    func authorizationStatus() async -> NotificationAuthorizationStatus { .authorized }
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
