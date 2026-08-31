import AppKit
import SwiftUI

struct SettingsView: View {
    let model: SettingsModel
    let appModel: AppModel

    var body: some View {
        #if DEBUG
        let _ = logChangesIfEnabled()
        #endif

        Form {
            Section("General") {
                Toggle(
                    "Show QuotaPulse in Menu Bar",
                    isOn: Binding(
                        get: { model.store.isMenuBarExtraRequested },
                        set: { requested in
                            model.setMenuBarExtraRequested(requested)
                            if !requested {
                                DispatchQueue.main.async {
                                    model.setMenuBarExtraRequested(false)
                                    NSApplication.shared.terminate(nil)
                                }
                            }
                        }
                    )
                )

                Toggle(
                    "Launch at Login",
                    isOn: Binding(
                        get: { model.launchAtLoginStatus == .enabled },
                        set: { model.setLaunchAtLoginEnabled($0) }
                    )
                )
                .disabled(
                    model.isUpdatingLaunchAtLogin
                        || model.launchAtLoginStatus == .requiresApproval
                )

                launchAtLoginStatus

                LabeledContent("Background refresh") {
                    Text("Every 15 minutes")
                }
            }

            Section("Providers") {
                Toggle(
                    "Codex",
                    isOn: Binding(
                        get: { model.store.isCodexEnabled },
                        set: { model.setProvider(.codex, enabled: $0) }
                    )
                )

                Toggle(
                    "Claude Code (Experimental, Unverified)",
                    isOn: Binding(
                        get: { model.store.isClaudeEnabled },
                        set: { model.setProvider(.claude, enabled: $0) }
                    )
                )
            }

            Section("Diagnostics") {
                if let diagnostics = model.diagnostics {
                    LabeledContent("QuotaPulse") {
                        Text(
                            diagnostics.appVersion.map { "\($0.value) (\(diagnostics.buildNumber?.value ?? "—"))" }
                                ?? "—"
                        )
                        .monospacedDigit()
                    }

                    ForEach(diagnostics.providers) { provider in
                        ProviderDiagnosticsView(diagnostics: provider)
                    }
                } else {
                    ProgressView("Loading diagnostics…")
                        .controlSize(.small)
                }

                Button("Copy Diagnostics", systemImage: "doc.on.doc") {
                    Task {
                        await model.copyDiagnostics()
                    }
                }
                .accessibilityHint(
                    "Copies a privacy-safe English report for GitHub Issues."
                )

                if let feedback = model.diagnosticsCopyFeedback {
                    Text(feedback)
                        .foregroundStyle(.secondary)
                }

                Text(
                    "Diagnostics exclude credentials, prompts, sessions, project data, private paths, and raw provider responses."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            Section("Notifications") {
                Toggle(
                    "Enable reset notifications",
                    isOn: Binding(
                        get: { model.store.areNotificationsEnabled },
                        set: { enabled in
                            Task { await model.setNotificationsEnabled(enabled) }
                        }
                    )
                )

                notificationPermissionStatus

                VStack(alignment: .leading, spacing: 8) {
                    Text("Short windows (up to 6 hours)")
                        .font(.headline)
                    Toggle(
                        "1-hour reminder",
                        isOn: reminderBinding(windowClass: .short, minutes: 60)
                    )
                    Toggle(
                        "30-minute reminder",
                        isOn: reminderBinding(windowClass: .short, minutes: 30)
                    )

                    Divider()

                    Text("Long windows")
                        .font(.headline)
                    Toggle(
                        "24-hour reminder",
                        isOn: reminderBinding(windowClass: .long, minutes: 24 * 60)
                    )
                    Toggle(
                        "6-hour reminder",
                        isOn: reminderBinding(windowClass: .long, minutes: 6 * 60)
                    )
                    Toggle(
                        "1-hour reminder",
                        isOn: reminderBinding(windowClass: .long, minutes: 60)
                    )
                }
                .disabled(!model.store.areNotificationsEnabled)
            }

            #if DEBUG
            Section("Development") {
                Button("Send test notification", systemImage: "bell.badge") {
                    Task {
                        await appModel.sendTestNotification()
                        await model.refreshSystemState()
                    }
                }
                .accessibilityHint(
                    "Requests notification permission if needed, then schedules a local notification for about five seconds from now."
                )

                Button("Log runtime snapshot", systemImage: "waveform.path.ecg") {
                    Task {
                        await appModel.logRuntimeDiagnosticsSnapshot()
                    }
                }
                .accessibilityHint(
                    "Writes a privacy-safe runtime diagnostics snapshot to Console."
                )

                if let notificationFeedback = appModel.notificationFeedback {
                    Text(notificationFeedback)
                        .foregroundStyle(.secondary)
                }

                if let runtimeDiagnosticsFeedback = appModel.runtimeDiagnosticsFeedback {
                    Text(runtimeDiagnosticsFeedback)
                        .foregroundStyle(.secondary)
                }
            }
            #endif
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 560)
        .padding()
        .task {
            await model.refreshSystemState()
            await model.refreshDiagnostics()
        }
    }

    @ViewBuilder
    private var launchAtLoginStatus: some View {
        if model.launchAtLoginUpdateFailed {
            Label(
                "Launch at Login could not be changed.",
                systemImage: "exclamationmark.triangle"
            )
            .foregroundStyle(.orange)
        } else {
            switch model.launchAtLoginStatus {
            case .requiresApproval:
                Text("Approval is required in System Settings > General > Login Items.")
                    .foregroundStyle(.secondary)
            case .unavailable:
                Text("Launch at Login is not registered with macOS yet.")
                    .foregroundStyle(.secondary)
            case .enabled, .disabled:
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private var notificationPermissionStatus: some View {
        switch model.notificationAuthorizationStatus {
        case .denied:
            Label(
                "Notifications are disabled in System Settings.",
                systemImage: "bell.slash"
            )
            .foregroundStyle(.secondary)
        case .notDetermined where model.store.areNotificationsEnabled:
            Text("macOS will ask for permission when the first reminder is ready.")
                .foregroundStyle(.secondary)
        case .authorized, .notDetermined:
            EmptyView()
        }
    }

    private func reminderBinding(
        windowClass: NotificationWindowClass,
        minutes: Int
    ) -> Binding<Bool> {
        Binding(
            get: {
                switch (windowClass, minutes) {
                case (.short, 60): model.store.isShortWindow1HourReminderEnabled
                case (.short, 30): model.store.isShortWindow30MinuteReminderEnabled
                case (.long, 24 * 60): model.store.is24HourReminderEnabled
                case (.long, 6 * 60): model.store.is6HourReminderEnabled
                case (.long, 60): model.store.is1HourReminderEnabled
                default: false
                }
            },
            set: { enabled in
                Task {
                    await model.setReminder(
                        windowClass: windowClass,
                        minutes: minutes,
                        enabled: enabled
                    )
                }
            }
        )
    }

    #if DEBUG
    private func logChangesIfEnabled() {
        guard RuntimeDiagnostics.logsSwiftUIChanges else { return }
        guard #available(macOS 14.1, *) else { return }
        Self._logChanges()
    }
    #endif
}

#Preview("Settings") {
    let appModel = AppDependencies.makePreviewModel()
    let store = SettingsStore(defaults: UserDefaults(suiteName: "SettingsPreview")!)
    let notifications = PreviewSettingsNotificationService()
    SettingsView(
        model: SettingsModel(
            store: store,
            appModel: appModel,
            notificationService: notifications,
            launchAtLoginController: PreviewLaunchAtLoginController()
        ),
        appModel: appModel
    )
}

@MainActor
private final class PreviewSettingsNotificationService: NotificationServicing {
    func evaluate(_ providerStates: [ProviderState], now: Date) async {}
    func authorizationStatus() async -> NotificationAuthorizationStatus { .authorized }
    #if DEBUG
    func sendTestNotification() async throws {}
    #endif
}

@MainActor
private final class PreviewLaunchAtLoginController: LaunchAtLoginControlling {
    var status: LaunchAtLoginStatus = .disabled
    func refreshStatus() {}
    func setEnabled(_ enabled: Bool) throws {
        status = enabled ? .enabled : .disabled
    }
}
