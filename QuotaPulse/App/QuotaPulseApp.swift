import SwiftUI

@main
struct QuotaPulseApp: App {
    @NSApplicationDelegateAdaptor(QuotaPulseApplicationDelegate.self)
    private var applicationDelegate
    @State private var runtime: AppDependencies.Runtime

    init() {
        let runtime = AppDependencies.makeRuntime()
        _runtime = State(initialValue: runtime)
        applicationDelegate.configure(settingsModel: runtime.settingsModel)
    }

    var body: some Scene {
        MenuBarExtra(
            isInserted: Binding(
                get: { runtime.settingsModel.isMenuBarExtraInserted },
                set: { runtime.settingsModel.menuBarExtraInsertionDidChange($0) }
            )
        ) {
            DashboardView(model: runtime.appModel)
        } label: {
            Label("QuotaPulse", systemImage: "gauge.with.dots.needle.50percent")
        }
        .menuBarExtraStyle(.window)

        // Apple may terminate an LSUIElement app whose only MenuBarExtra is removed.
        // Keep a non-menu-bar scene in the app lifecycle; AppKit presents recovery on demand.
        menuBarRecoveryScene

        Settings {
            SettingsView(model: runtime.settingsModel, appModel: runtime.appModel)
        }
    }

    private var menuBarRecoveryScene: some Scene {
        WindowGroup("QuotaPulse is hidden", id: MenuBarRecoveryPolicy.windowID) {
            MenuBarRecoveryScene(model: runtime.settingsModel)
        }
        .windowResizability(.contentSize)
        .commandsRemoved()
    }
}
