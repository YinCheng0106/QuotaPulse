import SwiftUI

struct ProviderStatePresentation: Equatable {
    static let defaultStaleInterval: TimeInterval = 15 * 60

    enum Kind: Equatable {
        case loading
        case available
        case stale
        case unavailable
        case error
    }

    let kind: Kind
    let badgeLabel: String
    let title: String
    let detail: String?
    let systemImageName: String
    let supportLabel: String?
    let showsStatusMessage: Bool

    init(
        state: ProviderState,
        now: Date = .now,
        staleInterval: TimeInterval = Self.defaultStaleInterval,
        locale: Locale = .autoupdatingCurrent
    ) {
        let hasUsage = state.snapshot?.windows.isEmpty == false
        let isSnapshotOld = state.snapshot.map {
            now.timeIntervalSince($0.capturedAt) >= staleInterval
        } ?? false
        let supportLabel = state.providerID == .claude
            ? AppLocalization.string("Experimental", locale: locale)
            : nil

        func localized(_ value: String.LocalizationValue) -> String {
            AppLocalization.string(value, locale: locale)
        }

        switch state.status {
        case .loading:
            self.init(
                kind: .loading,
                badgeLabel: hasUsage ? localized("Refreshing") : localized("Loading"),
                title: hasUsage ? localized("Refreshing…") : localized("Loading usage…"),
                detail: hasUsage ? nil : localized("Requesting current quota information."),
                systemImageName: "arrow.clockwise",
                supportLabel: supportLabel,
                showsStatusMessage: true
            )
        case .available where hasUsage && isSnapshotOld:
            self.init(
                kind: .stale,
                badgeLabel: localized("Out of date"),
                title: localized("Usage may be out of date"),
                detail: localized("Showing previously fetched usage."),
                systemImageName: "clock.badge.exclamationmark",
                supportLabel: supportLabel,
                showsStatusMessage: true
            )
        case .available where hasUsage:
            self.init(
                kind: .available,
                badgeLabel: localized("Available"),
                title: localized("Usage available"),
                detail: nil,
                systemImageName: "checkmark.circle",
                supportLabel: supportLabel,
                showsStatusMessage: false
            )
        case .available:
            self.init(
                kind: .unavailable,
                badgeLabel: localized("Unavailable"),
                title: localized("Usage data unavailable"),
                detail: localized("No quota windows are currently available."),
                systemImageName: "minus.circle",
                supportLabel: supportLabel,
                showsStatusMessage: true
            )
        case .disabled:
            self.init(
                kind: .unavailable,
                badgeLabel: localized("Disabled"),
                title: localized("Provider disabled"),
                detail: localized("Enable this provider in Settings to resume updates."),
                systemImageName: "pause.circle",
                supportLabel: supportLabel,
                showsStatusMessage: true
            )
        case .stale where hasUsage:
            self.init(
                kind: .stale,
                badgeLabel: localized("Stale"),
                title: localized("Showing previously fetched usage"),
                detail: localized("Usage may be out of date."),
                systemImageName: "clock.badge.exclamationmark",
                supportLabel: supportLabel,
                showsStatusMessage: true
            )
        case .stale:
            self.init(
                kind: .unavailable,
                badgeLabel: localized("Unavailable"),
                title: localized("Usage data unavailable"),
                detail: localized("No previously fetched quota information is available."),
                systemImageName: "minus.circle",
                supportLabel: supportLabel,
                showsStatusMessage: true
            )
        case .notConfigured:
            self.init(
                kind: .unavailable,
                badgeLabel: localized("Not configured"),
                title: state.providerID == .claude
                    ? localized("Claude Code is not configured")
                    : localized("Integration not configured"),
                detail: localized("Quota snapshot setup is required."),
                systemImageName: "gear.badge.questionmark",
                supportLabel: supportLabel,
                showsStatusMessage: true
            )
        case .notInstalled:
            self.init(
                kind: .unavailable,
                badgeLabel: localized("Not detected"),
                title: state.providerID == .codex
                    ? localized("Codex runtime not detected")
                    : localized("Provider not detected"),
                detail: state.providerID == .codex
                    ? localized("Open or install ChatGPT or Codex, then refresh.")
                    : localized("The local provider could not be found."),
                systemImageName: "square.dashed",
                supportLabel: supportLabel,
                showsStatusMessage: true
            )
        case .unsupportedAuthentication:
            self.init(
                kind: .unavailable,
                badgeLabel: localized("Unsupported"),
                title: localized("Usage data unavailable"),
                detail: localized("The current sign-in method does not provide quota information."),
                systemImageName: "person.crop.circle.badge.questionmark",
                supportLabel: supportLabel,
                showsStatusMessage: true
            )
        case let .failed(failure) where hasUsage:
            self.init(
                kind: .stale,
                badgeLabel: localized("Stale"),
                title: localized("Showing previously fetched usage"),
                detail: Self.failureTitle(failure, providerID: state.providerID, locale: locale),
                systemImageName: "clock.badge.exclamationmark",
                supportLabel: supportLabel,
                showsStatusMessage: true
            )
        case .failed(.usageUnavailable):
            self.init(
                kind: .unavailable,
                badgeLabel: localized("Unavailable"),
                title: localized("Usage data unavailable"),
                detail: localized("The provider did not return quota information."),
                systemImageName: "minus.circle",
                supportLabel: supportLabel,
                showsStatusMessage: true
            )
        case let .failed(failure):
            self.init(
                kind: .error,
                badgeLabel: localized("Error"),
                title: Self.failureTitle(failure, providerID: state.providerID, locale: locale),
                detail: localized("Previously fetched usage is not available."),
                systemImageName: "exclamationmark.triangle",
                supportLabel: supportLabel,
                showsStatusMessage: true
            )
        }
    }

    private static func failureTitle(
        _ failure: ProviderFailure,
        providerID: ProviderID,
        locale: Locale
    ) -> String {
        switch failure {
        case .runtimeLaunchFailed where providerID == .codex:
            AppLocalization.string("Unable to start Codex runtime", locale: locale)
        case .runtimeLaunchFailed, .refreshFailed:
            AppLocalization.string("Unable to refresh usage", locale: locale)
        case .usageUnavailable:
            AppLocalization.string("Usage data unavailable", locale: locale)
        }
    }

    private init(
        kind: Kind,
        badgeLabel: String,
        title: String,
        detail: String?,
        systemImageName: String,
        supportLabel: String?,
        showsStatusMessage: Bool
    ) {
        self.kind = kind
        self.badgeLabel = badgeLabel
        self.title = title
        self.detail = detail
        self.systemImageName = systemImageName
        self.supportLabel = supportLabel
        self.showsStatusMessage = showsStatusMessage
    }
}

struct ProviderStateView: View {
    let presentation: ProviderStatePresentation

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if presentation.kind == .loading {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 16, height: 16)
                    .accessibilityHidden(true)
            } else {
                Image(systemName: presentation.systemImageName)
                    .foregroundStyle(presentation.kind.tint)
                    .frame(width: 16)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(presentation.title)
                    .font(.callout.weight(.medium))

                if let detail = presentation.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}
