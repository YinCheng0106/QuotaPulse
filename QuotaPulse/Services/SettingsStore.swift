import Foundation
import Observation

struct NotificationPreferences: Equatable, Sendable {
    var isEnabled: Bool
    var enabledThresholdMinutes: [NotificationWindowClass: Set<Int>]

    static let defaults = NotificationPreferences(
        isEnabled: true,
        enabledThresholdMinutes: [
            .short: [60, 30],
            .long: [24 * 60, 6 * 60, 60],
        ]
    )

    func thresholds(for windowClass: NotificationWindowClass) -> Set<Int> {
        enabledThresholdMinutes[windowClass] ?? []
    }
}

@MainActor
protocol AppPreferencesProviding: AnyObject, Sendable {
    var notificationPreferences: NotificationPreferences { get }
    func isProviderEnabled(_ providerID: ProviderID) -> Bool
}

@Observable
@MainActor
final class SettingsStore: AppPreferencesProviding {
    private enum Key {
        static let menuBarExtraRequested = "presentation.menu-bar-extra.requested"
        static let codexEnabled = "providers.codex.enabled"
        static let claudeEnabled = "providers.claude.enabled"
        static let notificationsEnabled = "notifications.enabled"
        static let reminder24HoursEnabled = "notifications.reminder.24h.enabled"
        static let reminder6HoursEnabled = "notifications.reminder.6h.enabled"
        static let reminder1HourEnabled = "notifications.reminder.1h.enabled"
        static let shortWindowReminder1HourEnabled = "notifications.short-window.reminder.1h.enabled"
        static let shortWindowReminder30MinutesEnabled = "notifications.short-window.reminder.30m.enabled"
    }

    private let defaults: UserDefaults

    private(set) var isMenuBarExtraRequested: Bool
    private(set) var isCodexEnabled: Bool
    private(set) var isClaudeEnabled: Bool
    private(set) var areNotificationsEnabled: Bool
    private(set) var is24HourReminderEnabled: Bool
    private(set) var is6HourReminderEnabled: Bool
    private(set) var is1HourReminderEnabled: Bool
    private(set) var isShortWindow1HourReminderEnabled: Bool
    private(set) var isShortWindow30MinuteReminderEnabled: Bool

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isMenuBarExtraRequested = Self.bool(
            defaults,
            key: Key.menuBarExtraRequested,
            defaultValue: true
        )
        isCodexEnabled = Self.bool(defaults, key: Key.codexEnabled, defaultValue: true)
        isClaudeEnabled = Self.bool(defaults, key: Key.claudeEnabled, defaultValue: true)
        areNotificationsEnabled = Self.bool(defaults, key: Key.notificationsEnabled, defaultValue: true)
        is24HourReminderEnabled = Self.bool(defaults, key: Key.reminder24HoursEnabled, defaultValue: true)
        is6HourReminderEnabled = Self.bool(defaults, key: Key.reminder6HoursEnabled, defaultValue: true)
        is1HourReminderEnabled = Self.bool(defaults, key: Key.reminder1HourEnabled, defaultValue: true)
        let hasShortWindowOneHourPreference = defaults.object(
            forKey: Key.shortWindowReminder1HourEnabled
        ) != nil
        let shortWindowOneHourDefault = Self.bool(
            defaults,
            key: Key.reminder1HourEnabled,
            defaultValue: true
        )
        let shortWindowOneHourPreference = Self.bool(
            defaults,
            key: Key.shortWindowReminder1HourEnabled,
            defaultValue: shortWindowOneHourDefault
        )
        isShortWindow1HourReminderEnabled = shortWindowOneHourPreference
        if !hasShortWindowOneHourPreference {
            defaults.set(
                shortWindowOneHourPreference,
                forKey: Key.shortWindowReminder1HourEnabled
            )
        }
        isShortWindow30MinuteReminderEnabled = Self.bool(
            defaults,
            key: Key.shortWindowReminder30MinutesEnabled,
            defaultValue: true
        )
    }

    var notificationPreferences: NotificationPreferences {
        var shortWindowThresholds: Set<Int> = []
        if isShortWindow1HourReminderEnabled { shortWindowThresholds.insert(60) }
        if isShortWindow30MinuteReminderEnabled { shortWindowThresholds.insert(30) }

        var longWindowThresholds: Set<Int> = []
        if is24HourReminderEnabled { longWindowThresholds.insert(24 * 60) }
        if is6HourReminderEnabled { longWindowThresholds.insert(6 * 60) }
        if is1HourReminderEnabled { longWindowThresholds.insert(60) }
        return NotificationPreferences(
            isEnabled: areNotificationsEnabled,
            enabledThresholdMinutes: [
                .short: shortWindowThresholds,
                .long: longWindowThresholds,
            ]
        )
    }

    func isProviderEnabled(_ providerID: ProviderID) -> Bool {
        switch providerID {
        case .codex: isCodexEnabled
        case .claude: isClaudeEnabled
        }
    }

    func setProvider(_ providerID: ProviderID, enabled: Bool) {
        switch providerID {
        case .codex:
            isCodexEnabled = enabled
            defaults.set(enabled, forKey: Key.codexEnabled)
        case .claude:
            isClaudeEnabled = enabled
            defaults.set(enabled, forKey: Key.claudeEnabled)
        }
    }

    func setMenuBarExtraRequested(_ requested: Bool) {
        isMenuBarExtraRequested = requested
        defaults.set(requested, forKey: Key.menuBarExtraRequested)
        // Removing the only MenuBarExtra can terminate the process immediately.
        // Flush this presentation preference before that lifecycle transition.
        defaults.synchronize()
    }

    func setNotificationsEnabled(_ enabled: Bool) {
        areNotificationsEnabled = enabled
        defaults.set(enabled, forKey: Key.notificationsEnabled)
    }

    func setReminder(
        windowClass: NotificationWindowClass,
        minutes: Int,
        enabled: Bool
    ) {
        switch (windowClass, minutes) {
        case (.short, 60):
            isShortWindow1HourReminderEnabled = enabled
            defaults.set(enabled, forKey: Key.shortWindowReminder1HourEnabled)
        case (.short, 30):
            isShortWindow30MinuteReminderEnabled = enabled
            defaults.set(enabled, forKey: Key.shortWindowReminder30MinutesEnabled)
        case (.long, 24 * 60):
            is24HourReminderEnabled = enabled
            defaults.set(enabled, forKey: Key.reminder24HoursEnabled)
        case (.long, 6 * 60):
            is6HourReminderEnabled = enabled
            defaults.set(enabled, forKey: Key.reminder6HoursEnabled)
        case (.long, 60):
            is1HourReminderEnabled = enabled
            defaults.set(enabled, forKey: Key.reminder1HourEnabled)
        default:
            assertionFailure("Unsupported reset reminder threshold")
        }
    }

    private static func bool(_ defaults: UserDefaults, key: String, defaultValue: Bool) -> Bool {
        guard defaults.object(forKey: key) != nil else { return defaultValue }
        return defaults.bool(forKey: key)
    }
}
