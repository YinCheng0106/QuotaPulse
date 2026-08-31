import Foundation
import XCTest
@testable import QuotaPulse

@MainActor
final class SettingsStoreTests: XCTestCase {
    func testPersistedSettingsSurviveStoreRecreation() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let first = SettingsStore(defaults: defaults)

        first.setProvider(.codex, enabled: false)
        first.setProvider(.claude, enabled: false)
        first.setMenuBarExtraRequested(false)
        first.setNotificationsEnabled(false)
        first.setReminder(windowClass: .short, minutes: 60, enabled: false)
        first.setReminder(windowClass: .short, minutes: 30, enabled: false)
        first.setReminder(windowClass: .long, minutes: 24 * 60, enabled: false)
        first.setReminder(windowClass: .long, minutes: 6 * 60, enabled: false)
        first.setReminder(windowClass: .long, minutes: 60, enabled: false)

        let recreated = SettingsStore(defaults: defaults)

        XCTAssertFalse(recreated.isCodexEnabled)
        XCTAssertFalse(recreated.isClaudeEnabled)
        XCTAssertFalse(recreated.isMenuBarExtraRequested)
        XCTAssertFalse(recreated.areNotificationsEnabled)
        XCTAssertEqual(recreated.notificationPreferences.thresholds(for: .short), [])
        XCTAssertEqual(recreated.notificationPreferences.thresholds(for: .long), [])
    }

    func testNewStoreUsesV01Defaults() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SettingsStore(defaults: defaults)

        XCTAssertTrue(store.isCodexEnabled)
        XCTAssertTrue(store.isClaudeEnabled)
        XCTAssertTrue(store.isMenuBarExtraRequested)
        XCTAssertTrue(store.areNotificationsEnabled)
        XCTAssertEqual(store.notificationPreferences.thresholds(for: .short), [60, 30])
        XCTAssertEqual(
            store.notificationPreferences.thresholds(for: .long),
            [24 * 60, 6 * 60, 60]
        )
    }

    func testMenuBarVisibilityPreferenceDoesNotModifyProviderEnablement() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = SettingsStore(defaults: defaults)

        store.setMenuBarExtraRequested(false)

        XCTAssertFalse(store.isMenuBarExtraRequested)
        XCTAssertTrue(store.isCodexEnabled)
        XCTAssertTrue(store.isClaudeEnabled)
    }

    func testProviderEnablementDoesNotModifyMenuBarVisibilityPreference() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = SettingsStore(defaults: defaults)

        store.setProvider(.codex, enabled: false)
        store.setProvider(.claude, enabled: false)
        XCTAssertTrue(store.isMenuBarExtraRequested)

        store.setMenuBarExtraRequested(false)
        store.setProvider(.codex, enabled: true)
        store.setProvider(.claude, enabled: true)
        XCTAssertFalse(store.isMenuBarExtraRequested)
    }

    func testLegacyOneHourPreferenceMigratesToShortWindowSetting() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(false, forKey: "notifications.reminder.1h.enabled")

        let store = SettingsStore(defaults: defaults)

        XCTAssertFalse(store.isShortWindow1HourReminderEnabled)
        XCTAssertFalse(store.is1HourReminderEnabled)
        XCTAssertTrue(store.isShortWindow30MinuteReminderEnabled)
    }

    func testShortAndLongWindowReminderSettingsAreIndependent() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = SettingsStore(defaults: defaults)

        store.setReminder(windowClass: .short, minutes: 60, enabled: false)

        XCTAssertEqual(store.notificationPreferences.thresholds(for: .short), [30])
        XCTAssertEqual(
            store.notificationPreferences.thresholds(for: .long),
            [24 * 60, 6 * 60, 60]
        )

        store.setReminder(windowClass: .long, minutes: 60, enabled: false)

        XCTAssertEqual(store.notificationPreferences.thresholds(for: .short), [30])
        XCTAssertEqual(
            store.notificationPreferences.thresholds(for: .long),
            [24 * 60, 6 * 60]
        )

        let recreated = SettingsStore(defaults: defaults)
        XCTAssertEqual(recreated.notificationPreferences.thresholds(for: .short), [30])
        XCTAssertEqual(
            recreated.notificationPreferences.thresholds(for: .long),
            [24 * 60, 6 * 60]
        )
    }

    func testMigratedShortWindowPreferenceStaysIndependentAfterRestart() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: "notifications.reminder.1h.enabled")
        let first = SettingsStore(defaults: defaults)

        first.setReminder(windowClass: .long, minutes: 60, enabled: false)
        let recreated = SettingsStore(defaults: defaults)

        XCTAssertTrue(recreated.isShortWindow1HourReminderEnabled)
        XCTAssertFalse(recreated.is1HourReminderEnabled)
    }

    private func makeDefaults() -> (UserDefaults, String) {
        let suiteName = "dev.quotapulse.tests.settings.\(UUID().uuidString)"
        return (UserDefaults(suiteName: suiteName)!, suiteName)
    }
}
