import AppKit
import SwiftUI

struct MenuBarRecoveryView: View {
    let model: SettingsModel
    let showInMenuBar: @MainActor () -> Void
    let quit: @MainActor () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label {
                Text("QuotaPulse is hidden")
                    .font(.title2.weight(.semibold))
            } icon: {
                Image(systemName: "menubar.rectangle")
                    .font(.title2)
                    .foregroundStyle(.tint)
            }

            Text("QuotaPulse is currently hidden from the menu bar.")

            Text(
                "If it does not appear after you show it, allow QuotaPulse in System Settings > Menu Bar."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("Quit QuotaPulse") {
                    quit()
                }

                Spacer()

                SettingsLink {
                    Text("Open Settings")
                }

                Button("Show in Menu Bar") {
                    showInMenuBar()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 430)
    }
}

@MainActor
final class QuotaPulseApplicationDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var settingsModel: SettingsModel?
    private var recoveryWindowController: NSWindowController?
    private var previousActivationPolicy: NSApplication.ActivationPolicy?

    func configure(settingsModel: SettingsModel) {
        self.settingsModel = settingsModel
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let settingsModel else { return }
        guard !AppRuntimeEnvironment.isRunningTests else { return }
        let disposition = MenuBarRecoveryPolicy.disposition(
            isMenuBarExtraRequested: settingsModel.store.isMenuBarExtraRequested,
            launchSource: ApplicationLaunchSourceDetector.current()
        )

        switch disposition {
        case .normal:
            scheduleBlockedLaunchRecovery(settingsModel: settingsModel)
        case .recovery:
            showRecoveryWindow(settingsModel: settingsModel)
        case .quietExit:
            NSApplication.shared.terminate(nil)
        }
    }

    func windowWillClose(_ notification: Notification) {
        endRecoveryPresentation()
        recoveryWindowController = nil
        guard settingsModel?.isMenuBarExtraInserted == false else { return }
        DispatchQueue.main.async {
            NSApplication.shared.terminate(nil)
        }
    }

    private func scheduleBlockedLaunchRecovery(settingsModel: SettingsModel) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self, weak settingsModel] in
            guard
                let self,
                let settingsModel,
                settingsModel.store.isMenuBarExtraRequested,
                !settingsModel.isMenuBarExtraInserted
            else {
                return
            }
            self.showRecoveryWindow(settingsModel: settingsModel)
        }
    }

    private func showRecoveryWindow(settingsModel: SettingsModel) {
        guard recoveryWindowController == nil else { return }
        beginRecoveryPresentation()
        let rootView = MenuBarRecoveryView(
            model: settingsModel,
            showInMenuBar: { [weak self] in
                settingsModel.setMenuBarExtraRequested(true)
                self?.recoveryWindowController?.window?.makeKeyAndOrderFront(nil)
            },
            quit: {
                NSApplication.shared.terminate(nil)
            }
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 430, height: 220),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = String(localized: "QuotaPulse is hidden")
        window.contentViewController = NSHostingController(rootView: rootView)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()

        let controller = NSWindowController(window: window)
        recoveryWindowController = controller
        controller.showWindow(nil)
        NSApplication.shared.activate()
    }

    private func beginRecoveryPresentation() {
        guard previousActivationPolicy == nil else { return }
        let application = NSApplication.shared
        previousActivationPolicy = application.activationPolicy()
        if application.activationPolicy() != .regular {
            application.setActivationPolicy(.regular)
        }
    }

    private func endRecoveryPresentation() {
        guard let previousActivationPolicy else { return }
        let application = NSApplication.shared
        if application.activationPolicy() != previousActivationPolicy {
            application.setActivationPolicy(previousActivationPolicy)
        }
        self.previousActivationPolicy = nil
    }
}

#Preview("Menu Bar Recovery") {
    let appModel = AppDependencies.makePreviewModel()
    let store = SettingsStore(defaults: UserDefaults(suiteName: "RecoveryPreview")!)
    MenuBarRecoveryView(
        model: SettingsModel(
            store: store,
            appModel: appModel,
            notificationService: PreviewMenuBarRecoveryNotificationService(),
            launchAtLoginController: PreviewMenuBarRecoveryLaunchAtLoginController()
        ),
        showInMenuBar: {},
        quit: {}
    )
}

@MainActor
private final class PreviewMenuBarRecoveryNotificationService: NotificationServicing {
    func evaluate(_ providerStates: [ProviderState], now: Date) async {}
    #if DEBUG
    func sendTestNotification() async throws {}
    #endif
}

@MainActor
private final class PreviewMenuBarRecoveryLaunchAtLoginController: LaunchAtLoginControlling {
    var status: LaunchAtLoginStatus = .disabled
    func refreshStatus() {}
    func setEnabled(_ enabled: Bool) throws {
        status = enabled ? .enabled : .disabled
    }
}
