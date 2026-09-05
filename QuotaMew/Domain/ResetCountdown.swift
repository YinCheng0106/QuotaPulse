import Foundation

enum ResetCountdown {
    static func text(
        until resetAt: Date?,
        now: Date,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        guard let resetAt else {
            return AppLocalization.string("Reset time unavailable", locale: locale)
        }

        let seconds = resetAt.timeIntervalSince(now)
        guard seconds > 0 else {
            return AppLocalization.string("Refresh needed", locale: locale)
        }

        let totalMinutes = Int((seconds / 60).rounded(.up))
        return AppLocalization.countdownDuration(totalMinutes: totalMinutes, locale: locale)
            ?? AppLocalization.string("Reset time unavailable", locale: locale)
    }
}
