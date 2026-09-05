import Foundation

/// A display-only projection of a normalized quota window.
///
/// This deliberately does not participate in provider mapping, reset detection,
/// or notification policy. Those consumers continue to use `UsageWindow`.
struct UsagePresentation: Equatable, Sendable {
    let mode: UsagePresentationMode
    let percentage: Int?

    init(window: UsageWindow, mode: UsagePresentationMode) {
        self.mode = mode
        switch mode {
        case .remaining:
            percentage = window.remainingPercentage.map { Int($0.rounded()) }
        case .used:
            percentage = window.displayUsedPercentage.map { Int($0.rounded()) }
        }
    }

    func text(locale: Locale) -> String? {
        guard let percentage else { return nil }
        return switch mode {
        case .remaining:
            AppLocalization.remainingPercentage(percentage, locale: locale)
        case .used:
            AppLocalization.usedPercentage(percentage, locale: locale)
        }
    }

    func compactText(locale: Locale) -> String? {
        guard let percentage else { return nil }
        return (Double(percentage) / 100).formatted(
            .percent.precision(.fractionLength(0)).locale(locale)
        )
    }
}
