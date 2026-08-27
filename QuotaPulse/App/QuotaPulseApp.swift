import SwiftUI

@main
struct QuotaPulseApp: App {
    @State private var runtime = AppDependencies.makeRuntime()

    var body: some Scene {
        MenuBarExtra {
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
