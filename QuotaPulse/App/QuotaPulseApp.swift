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

        Settings {
            SettingsView(model: runtime.settingsModel, appModel: runtime.appModel)
        }
    }
}
