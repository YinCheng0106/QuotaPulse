import AppKit
import SwiftUI

struct DashboardView: View {
    let model: AppModel

    var body: some View {
        #if DEBUG
        let _ = logChangesIfEnabled()
        #endif

        VStack(spacing: 12) {
            let activeProviderStates = model.activeProviderStates
            let isRefreshingEnabledProviders = model.isRefreshing && model.hasEnabledProviders
            DashboardHeaderView(
                status: DashboardHeaderStatus(
                    isRefreshing: isRefreshingEnabledProviders,
                    hasLoadingProvider: activeProviderStates.contains {
                        $0.status == .loading
                    },
                    lastUpdatedAt: model.lastUpdatedAt
                ),
                isRefreshing: isRefreshingEnabledProviders,
                canRefresh: model.hasEnabledProviders,
                onRefresh: refresh
            )

            if activeProviderStates.isEmpty {
                DashboardEmptyStateView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(activeProviderStates) { state in
                            ProviderCardView(state: state)
                        }
                    }
                    .padding(.vertical, 1)
                }
                .scrollIndicators(.never)
            }

            DashboardActionsView(
                onQuit: quit
            )
        }
        .padding(12)
        .frame(width: 348, height: 500)
        .onAppear {
            model.menuDidOpen()
        }
    }

    private func refresh() {
        model.refreshManually()
    }

    private func quit() {
        NSApplication.shared.terminate(nil)
    }

    #if DEBUG
    private func logChangesIfEnabled() {
        guard RuntimeDiagnostics.logsSwiftUIChanges else { return }
        guard #available(macOS 14.1, *) else { return }
        Self._logChanges()
    }
    #endif
}

private struct DashboardEmptyStateView: View {
    var body: some View {
        ContentUnavailableView {
            Label("No providers enabled", systemImage: "pause.circle")
        } description: {
            Text("Enable a provider in Settings to start monitoring usage.")
        } actions: {
            SettingsLink {
                Text("Open Settings")
            }
        }
    }
}

enum DashboardHeaderStatus: Equatable {
    case loading
    case updated(Date)
    case unavailable

    init(
        isRefreshing: Bool,
        hasLoadingProvider: Bool,
        lastUpdatedAt: Date?
    ) {
        if isRefreshing || hasLoadingProvider {
            self = .loading
        } else if let lastUpdatedAt {
            self = .updated(lastUpdatedAt)
        } else {
            self = .unavailable
        }
    }
}

private struct DashboardHeaderView: View {
    let status: DashboardHeaderStatus
    let isRefreshing: Bool
    let canRefresh: Bool
    let onRefresh: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("QuotaPulse")
                    .font(.headline)
                switch status {
                case .loading:
                    Text("Updating provider usage…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case let .updated(lastUpdatedAt):
                    Text("Updated \(lastUpdatedAt, format: .dateTime.hour().minute())")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .unavailable:
                    Text("Provider usage unavailable")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button("Refresh usage", systemImage: "arrow.clockwise", action: onRefresh)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .keyboardShortcut("r", modifiers: .command)
                .disabled(isRefreshing || !canRefresh)
                .help("Refresh usage (⌘R)")
                .accessibilityHint("Refreshes provider usage")
        }
        .padding(.horizontal, 2)
    }
}

private struct DashboardActionsView: View {
    let onQuit: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Divider()

            HStack(spacing: 12) {
                SettingsLink {
                    Label("Settings", systemImage: "gear")
                }

                Spacer()

                Button("Quit QuotaPulse", action: onQuit)
                    .keyboardShortcut("q", modifiers: .command)
            }
            .controlSize(.small)
        }
    }
}

#Preview("Dashboard") {
    DashboardView(model: AppDependencies.makePreviewModel())
}
