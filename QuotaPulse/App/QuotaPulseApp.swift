import SwiftUI

@main
struct QuotaPulseApp: App {
    @NSApplicationDelegateAdaptor(QuotaPulseApplicationDelegate.self)
    private var applicationDelegate
    @State private var runtime: AppDependencies.Runtime

    init() {
        let runtime = AppDependencies.makeRuntime()
        _runtime = State(initialValue: runtime)
        applicationDelegate.configure(
            appModel: runtime.appModel,
            settingsModel: runtime.settingsModel
        )
    }

    var body: some Scene {
        Settings {
            SettingsView(model: runtime.settingsModel, appModel: runtime.appModel)
        }
    }
}
