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
            MenuBarContent(
                appModel: runtime.appModel,
                settingsModel: runtime.settingsModel
            )
        } label: {
            MenuBarLabel(settingsModel: runtime.settingsModel)
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

private struct MenuBarContent: View {
    let appModel: AppModel
    let settingsModel: SettingsModel

    var body: some View {
        DashboardView(
            model: appModel,
            usagePresentationMode: settingsModel.usagePresentationMode
        )
    }
}

private struct MenuBarLabel: View {
    @Environment(\.locale) private var locale

    let settingsModel: SettingsModel

    var body: some View {
        let presentation = settingsModel.menuBarPresentation
        HStack(spacing: 4) {
            Image(systemName: "gauge.with.dots.needle.50percent")
            Text(presentation.usage?.compactText(locale: locale) ?? "—")
                .monospacedDigit()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(for: presentation))
        .accessibilityValue(accessibilityValue(for: presentation))
    }

    private func accessibilityLabel(for presentation: MenuBarPresentation) -> String {
        presentation.selectedProvider?.displayName ?? "QuotaPulse"
    }

    private func accessibilityValue(for presentation: MenuBarPresentation) -> String {
        guard let usage = presentation.usage?.text(locale: locale) else {
            return switch presentation.availability {
            case .renderable:
                AppLocalization.string("Menu bar usage unavailable", locale: locale)
            case .disabled:
                AppLocalization.string("Disabled", locale: locale)
            case .unavailable:
                AppLocalization.string("Unavailable", locale: locale)
            case .empty:
                AppLocalization.string("No providers enabled", locale: locale)
            }
        }
        return usage
    }
}
