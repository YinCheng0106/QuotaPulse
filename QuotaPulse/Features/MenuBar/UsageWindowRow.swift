import SwiftUI

struct UsageWindowRow: View {
    @Environment(\.locale) private var locale

    let window: UsageWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()

            HStack {
                Text(window.label)
                    .font(.subheadline.weight(.medium))
                Spacer()
                if let roundedUsedPercentage = window.roundedUsedPercentage {
                    Text(AppLocalization.usedPercentage(roundedUsedPercentage, locale: locale))
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .accessibilityLabel(
                            AppLocalization.usedPercentage(roundedUsedPercentage, locale: locale)
                        )
                } else {
                    Text("Usage unavailable")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let progress = window.progress {
                ProgressView(value: progress)
                    .tint(window.progressTint)
                    .accessibilityHidden(true)
            }

            HStack {
                if let roundedRemainingPercentage = window.roundedRemainingPercentage {
                    Text(
                        AppLocalization.remainingPercentage(
                            roundedRemainingPercentage,
                            locale: locale
                        )
                    )
                        .monospacedDigit()
                }
                Spacer()
                if let resetAt = window.resetAt {
                    ResetCountdownView(resetAt: resetAt)
                } else {
                    Text("Reset time unavailable")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct ResetCountdownView: View {
    @Environment(\.locale) private var locale

    let resetAt: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let countdown = ResetCountdown.text(
                until: resetAt,
                now: context.date,
                locale: locale
            )
            Text(
                resetAt > context.date
                    ? AppLocalization.resetCountdown(countdown, locale: locale)
                    : countdown
            )
                .monospacedDigit()
                .help(Text("Resets \(resetAt, format: .dateTime.month(.abbreviated).day().hour().minute())"))
        }
    }
}

private extension UsageWindow {
    var roundedUsedPercentage: Int? {
        displayUsedPercentage.map { Int($0.rounded()) }
    }

    var roundedRemainingPercentage: Int? {
        remainingPercentage.map { Int($0.rounded()) }
    }

    var progressTint: Color {
        switch displayUsedPercentage ?? 0 {
        case 85...:
            .red
        case 65...:
            .orange
        default:
            .accentColor
        }
    }
}
