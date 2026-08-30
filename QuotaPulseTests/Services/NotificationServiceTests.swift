import XCTest
import UserNotifications
@testable import QuotaPulse

@MainActor
final class NotificationServiceTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    func testWeeklyWindowSupportsTwentyFourHourReminder() async throws {
        let (service, center, _) = makeService()

        await service.evaluate(
            [makeState(resetAfter: 24 * 3_600, duration: .seconds(7 * 24 * 3_600), usedPercentage: 39)],
            now: now
        )

        let request = try XCTUnwrap(center.requests.first)
        XCTAssertEqual(center.requests.count, 1)
        XCTAssertEqual(request.title, "Codex resets in 24 hours")
        XCTAssertEqual(request.body, "You still have 61% of your quota remaining.")
    }

    func testWeeklyWindowSupportsSixHourReminder() async throws {
        let (service, center, store) = makeService()

        await service.evaluate(
            [makeState(resetAfter: 6 * 3_600, duration: .seconds(7 * 24 * 3_600), usedPercentage: 39)],
            now: now
        )

        let request = try XCTUnwrap(center.requests.first)
        XCTAssertEqual(center.requests.count, 1)
        XCTAssertEqual(request.title, "Codex resets in 6 hours")
        XCTAssertEqual(store.state.entries.first?.emittedThresholdMinutes, [24 * 60, 6 * 60])
    }

    func testWeeklyWindowSupportsOneHourReminder() async throws {
        let (service, center, store) = makeService()

        await service.evaluate(
            [makeState(resetAfter: 60 * 60, duration: .seconds(7 * 24 * 3_600), usedPercentage: 39)],
            now: now
        )

        let request = try XCTUnwrap(center.requests.first)
        XCTAssertEqual(center.requests.count, 1)
        XCTAssertEqual(request.title, "Codex resets in 1 hour")
        XCTAssertEqual(
            store.state.entries.first?.emittedThresholdMinutes,
            [24 * 60, 6 * 60, 60]
        )
    }

    func testFiveHourWindowDoesNotScheduleSixHourReminder() async {
        let (service, center, _) = makeService()

        await service.evaluate(
            [makeState(resetAfter: 5 * 3_600, duration: .seconds(5 * 3_600))],
            now: now
        )

        XCTAssertTrue(center.requests.isEmpty)
    }

    func testFiveHourWindowSupportsOneHourReminder() async throws {
        let (service, center, store) = makeService()

        await service.evaluate(
            [makeState(resetAfter: 60 * 60, duration: .seconds(5 * 3_600))],
            now: now
        )

        let request = try XCTUnwrap(center.requests.first)
        XCTAssertEqual(request.title, "Codex resets in 1 hour")
        XCTAssertTrue(request.identifier.hasSuffix(".short.60m"))
        XCTAssertEqual(store.state.entries.first?.emittedThresholdMinutes, [60])
    }

    func testFiveHourWindowSupportsThirtyMinuteReminder() async throws {
        let (service, center, store) = makeService()

        await service.evaluate(
            [makeState(resetAfter: 30 * 60, duration: .seconds(5 * 3_600))],
            now: now
        )

        let request = try XCTUnwrap(center.requests.first)
        XCTAssertEqual(request.title, "Codex resets in 30 minutes")
        XCTAssertTrue(request.identifier.hasSuffix(".short.30m"))
        XCTAssertEqual(store.state.entries.first?.emittedThresholdMinutes, [60, 30])
    }

    func testWindowSpecificSettingsMapToMatchingQuotaWindows() async {
        let suiteName = "dev.quotapulse.tests.notifications.window-settings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = SettingsStore(defaults: defaults)
        preferences.setReminder(windowClass: .short, minutes: 60, enabled: false)
        let center = TestUserNotificationCenter()
        let service = NotificationService(
            center: center,
            stateStore: TestNotificationStateStore(),
            preferences: preferences
        )

        await service.evaluate(
            [makeState(windowID: "short", resetAfter: 60 * 60, duration: .seconds(5 * 3_600))],
            now: now
        )
        await service.evaluate(
            [makeState(windowID: "weekly", resetAfter: 60 * 60, duration: .seconds(7 * 24 * 3_600))],
            now: now
        )

        XCTAssertEqual(center.requests.count, 1)
        XCTAssertTrue(center.requests[0].identifier.hasSuffix(".long.60m"))
    }

    func testRepeatedRefreshDoesNotDuplicateNotification() async {
        let (service, center, _) = makeService()
        let states = [makeState(resetAfter: 6 * 3_600)]

        await service.evaluate(states, now: now)
        await service.evaluate(states, now: now.addingTimeInterval(60))

        XCTAssertEqual(center.requests.count, 1)
    }

    func testConcurrentEvaluationDoesNotDuplicateNotification() async {
        let (service, center, _) = makeService(status: .notDetermined)
        center.yieldsBeforeReturningAuthorizationStatus = true
        let states = [makeState(resetAfter: 6 * 3_600)]
        let currentDate = now

        let first = Task { @MainActor in
            await service.evaluate(states, now: currentDate)
        }
        let second = Task { @MainActor in
            await service.evaluate(states, now: currentDate)
        }
        await first.value
        await second.value

        XCTAssertEqual(center.authorizationRequestCount, 1)
        XCTAssertEqual(center.requests.count, 1)
    }

    func testSnapshotThatBecomesStaleWhileAwaitingPermissionDoesNotNotify() async {
        let clock = TestDateSource(now)
        let center = TestUserNotificationCenter(status: .notDetermined)
        center.onRequestAuthorization = {
            clock.advance(by: 16 * 60)
        }
        let service = NotificationService(
            center: center,
            stateStore: TestNotificationStateStore(),
            currentDate: { clock.now }
        )

        await service.evaluate(
            [makeState(resetAfter: 6 * 3_600)],
            now: now
        )

        XCTAssertTrue(center.requests.isEmpty)
    }

    func testAppRestartDoesNotDuplicateNotification() async {
        let suiteName = "dev.quotapulse.tests.notifications.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let firstCenter = TestUserNotificationCenter()
        let firstService = NotificationService(
            center: firstCenter,
            stateStore: UserDefaultsNotificationStateStore(
                defaults: defaults,
                key: "deduplication"
            )
        )
        let states = [makeState(resetAfter: 6 * 3_600)]

        await firstService.evaluate(states, now: now)

        let relaunchedCenter = TestUserNotificationCenter()
        let relaunchedService = NotificationService(
            center: relaunchedCenter,
            stateStore: UserDefaultsNotificationStateStore(
                defaults: defaults,
                key: "deduplication"
            )
        )
        await relaunchedService.evaluate(states, now: now.addingTimeInterval(60))

        XCTAssertEqual(firstCenter.requests.count, 1)
        XCTAssertTrue(relaunchedCenter.requests.isEmpty)
    }

    func testGenuineLocalResetEmitsOneLocalizedCompletedNotification() async throws {
        let (preferences, defaults, suiteName) = makePreferencesWithRemindersDisabled()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let center = TestUserNotificationCenter()
        let store = TestNotificationStateStore()
        let service = NotificationService(
            center: center,
            stateStore: store,
            preferences: preferences,
            locale: Locale(identifier: "en")
        )
        let oldReset = now.addingTimeInterval(60 * 60)

        await service.evaluate(
            [makeState(
                resetAt: oldReset,
                duration: .seconds(5 * 60 * 60),
                usedPercentage: 82,
                capturedAt: now
            )],
            now: now
        )
        let afterCapture = oldReset.addingTimeInterval(30)
        let refreshedState = makeState(
            resetAt: oldReset.addingTimeInterval(5 * 60 * 60),
            duration: .seconds(5 * 60 * 60),
            usedPercentage: 1,
            capturedAt: afterCapture
        )
        await service.evaluate([refreshedState], now: afterCapture)
        await service.evaluate(
            [makeState(
                resetAt: oldReset.addingTimeInterval(5 * 60 * 60),
                duration: .seconds(5 * 60 * 60),
                usedPercentage: 1,
                capturedAt: afterCapture.addingTimeInterval(60)
            )],
            now: afterCapture.addingTimeInterval(60)
        )

        let request = try XCTUnwrap(center.requests.first)
        XCTAssertEqual(center.requests.count, 1)
        XCTAssertTrue(request.identifier.hasPrefix("quotapulse.reset-completed.codex."))
        XCTAssertEqual(request.title, "Codex quota reset")
        XCTAssertEqual(request.body, "Your 5-hour usage window has refreshed.")
    }

    func testRestartDoesNotDuplicateCompletedResetNotification() async {
        let suiteName = "dev.quotapulse.tests.local-reset-restart.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = SettingsStore(defaults: defaults)
        disableAllReminders(in: preferences)
        let key = "local-reset-deduplication"
        let firstCenter = TestUserNotificationCenter()
        let firstService = NotificationService(
            center: firstCenter,
            stateStore: UserDefaultsNotificationStateStore(defaults: defaults, key: key),
            preferences: preferences,
            locale: Locale(identifier: "en")
        )
        let oldReset = now.addingTimeInterval(60 * 60)
        await firstService.evaluate(
            [makeState(
                resetAt: oldReset,
                duration: .seconds(5 * 60 * 60),
                usedPercentage: 82,
                capturedAt: now
            )],
            now: now
        )
        let afterCapture = oldReset.addingTimeInterval(30)
        let nextReset = oldReset.addingTimeInterval(5 * 60 * 60)
        await firstService.evaluate(
            [makeState(
                resetAt: nextReset,
                duration: .seconds(5 * 60 * 60),
                usedPercentage: 1,
                capturedAt: afterCapture
            )],
            now: afterCapture
        )

        let relaunchedCenter = TestUserNotificationCenter()
        let relaunchedService = NotificationService(
            center: relaunchedCenter,
            stateStore: UserDefaultsNotificationStateStore(defaults: defaults, key: key),
            preferences: preferences,
            locale: Locale(identifier: "en")
        )
        await relaunchedService.evaluate(
            [makeState(
                resetAt: nextReset,
                duration: .seconds(5 * 60 * 60),
                usedPercentage: 1,
                capturedAt: afterCapture.addingTimeInterval(60)
            )],
            now: afterCapture.addingTimeInterval(60)
        )

        XCTAssertEqual(firstCenter.requests.count, 1)
        XCTAssertTrue(relaunchedCenter.requests.isEmpty)
    }

    func testRepeatedManualRefreshDoesNotDuplicateNotification() async {
        let center = TestUserNotificationCenter()
        let notificationService = NotificationService(
            center: center,
            stateStore: TestNotificationStateStore()
        )
        let provider = StaticNotificationProvider(
            snapshot: makeState(resetAfter: 6 * 3_600).snapshot!
        )
        let currentDate = now
        let model = AppModel(
            providerIDs: [.codex],
            refreshCoordinator: RefreshCoordinator(
                usageService: UsageService(providers: [provider])
            ),
            notificationService: notificationService,
            now: { currentDate },
            observesLifecycle: false
        )

        await model.refresh()
        await model.refresh()

        XCTAssertEqual(center.requests.count, 1)
        let fetchCount = await provider.fetchCount
        XCTAssertEqual(fetchCount, 2)
    }

    func testGenuinelyNewResetWindowBecomesEligibleAfterPreviousResetPasses() async throws {
        let (service, center, _) = makeService()
        let firstReset = now.addingTimeInterval(6 * 3_600)
        await service.evaluate(
            [makeState(resetAt: firstReset, capturedAt: now)],
            now: now
        )

        let nextNow = firstReset.addingTimeInterval(60)
        let nextReset = nextNow.addingTimeInterval(6 * 3_600)
        await service.evaluate(
            [makeState(resetAt: nextReset, capturedAt: nextNow)],
            now: nextNow
        )

        XCTAssertEqual(center.requests.count, 2)
        XCTAssertNotEqual(center.requests[0].identifier, center.requests[1].identifier)
    }

    func testResetTimestampMoveWithinActiveWindowDoesNotReissueThreshold() async {
        let (service, center, _) = makeService()
        await service.evaluate(
            [makeState(resetAfter: 6 * 3_600)],
            now: now
        )

        let laterCapture = now.addingTimeInterval(60)
        await service.evaluate(
            [makeState(
                resetAt: now.addingTimeInterval(8 * 3_600),
                capturedAt: laterCapture
            )],
            now: laterCapture
        )
        let crossedAgain = now.addingTimeInterval(2 * 3_600 + 60)
        await service.evaluate(
            [makeState(
                resetAt: now.addingTimeInterval(8 * 3_600),
                capturedAt: crossedAgain
            )],
            now: crossedAgain
        )

        XCTAssertEqual(center.requests.count, 1)
    }

    func testResetTimestampMoveEarlierWithinActiveWindowUsesNewThresholdTiming() async throws {
        let (service, center, store) = makeService()
        await service.evaluate(
            [makeState(resetAfter: 30 * 3_600)],
            now: now
        )
        let originalIdentity = try XCTUnwrap(
            store.state.entries.first?.resetWindowIdentityMinute
        )

        let nextNow = now.addingTimeInterval(60)
        await service.evaluate(
            [makeState(
                resetAt: nextNow.addingTimeInterval(5 * 3_600),
                capturedAt: nextNow
            )],
            now: nextNow
        )

        XCTAssertEqual(center.requests.count, 1)
        XCTAssertEqual(center.requests.first?.title, "Codex resets in 6 hours")
        XCTAssertEqual(
            store.state.entries.first?.resetWindowIdentityMinute,
            originalIdentity
        )
    }

    func testPassedResetWindowDoesNotNotify() async {
        let (service, center, _) = makeService()

        await service.evaluate(
            [makeState(resetAfter: -60)],
            now: now
        )

        XCTAssertTrue(center.requests.isEmpty)
    }

    func testMissingResetTimestampDoesNotNotify() async {
        let (service, center, _) = makeService()

        await service.evaluate(
            [makeState(resetAt: nil, capturedAt: now)],
            now: now
        )

        XCTAssertTrue(center.requests.isEmpty)
    }

    func testMissingUsagePercentageSendsSimpleResetReminder() async throws {
        let (service, center, _) = makeService()

        await service.evaluate(
            [makeState(resetAfter: 6 * 3_600, usedPercentage: nil)],
            now: now
        )

        let request = try XCTUnwrap(center.requests.first)
        XCTAssertEqual(request.title, "Codex resets in 6 hours")
        XCTAssertEqual(request.body, "Your quota window is approaching its scheduled reset.")
        XCTAssertFalse(request.body.contains("%"))
    }

    func testStaleSnapshotDoesNotNotifyOrRequestPermission() async {
        let (service, center, _) = makeService(status: .notDetermined)

        await service.evaluate(
            [makeState(
                resetAfter: 6 * 3_600,
                capturedAt: now.addingTimeInterval(-(16 * 60))
            )],
            now: now
        )

        XCTAssertTrue(center.requests.isEmpty)
        XCTAssertEqual(center.authorizationRequestCount, 0)
    }

    func testMockSnapshotDoesNotNotifyOrRequestPermission() async {
        let (service, center, _) = makeService(status: .notDetermined)
        let realState = makeState(resetAfter: 6 * 3_600)
        let snapshot = realState.snapshot!
        let mockState = ProviderState(
            providerID: realState.providerID,
            status: .available,
            snapshot: ProviderUsageSnapshot(
                providerID: snapshot.providerID,
                windows: snapshot.windows,
                capturedAt: snapshot.capturedAt,
                source: UsageSource(kind: .mock, label: "Test", documentationURL: nil)
            )
        )

        await service.evaluate([mockState], now: now)

        XCTAssertTrue(center.requests.isEmpty)
        XCTAssertEqual(center.authorizationRequestCount, 0)
    }

    func testPermanentlyUnavailableProviderDoesNotNotify() async {
        let (service, center, _) = makeService()
        let staleCachedState = makeState(
            status: .notInstalled,
            resetAfter: 6 * 3_600
        )

        await service.evaluate([staleCachedState], now: now)

        XCTAssertTrue(center.requests.isEmpty)
    }

    func testDeniedPermissionDoesNotNotifyOrPromptAgain() async {
        let (service, center, store) = makeService(status: .denied)

        await service.evaluate(
            [makeState(resetAfter: 6 * 3_600)],
            now: now
        )

        XCTAssertTrue(center.requests.isEmpty)
        XCTAssertEqual(center.authorizationRequestCount, 0)
        XCTAssertEqual(store.state.entries.first?.emittedThresholdMinutes, [])
    }

    func testDisabledNotificationPreferenceSuppressesNotification() async {
        let suiteName = "dev.quotapulse.tests.notifications.preferences.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = SettingsStore(defaults: defaults)
        preferences.setNotificationsEnabled(false)
        let center = TestUserNotificationCenter(status: .notDetermined)
        let service = NotificationService(
            center: center,
            stateStore: TestNotificationStateStore(),
            preferences: preferences
        )

        await service.evaluate([makeState(resetAfter: 6 * 3_600)], now: now)

        XCTAssertTrue(center.requests.isEmpty)
        XCTAssertEqual(center.authorizationRequestCount, 0)
    }

    func testDisabledThresholdDoesNotScheduleNotification() async {
        let suiteName = "dev.quotapulse.tests.notifications.threshold.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = SettingsStore(defaults: defaults)
        preferences.setReminder(windowClass: .long, minutes: 24 * 60, enabled: false)
        preferences.setReminder(windowClass: .long, minutes: 6 * 60, enabled: false)
        let center = TestUserNotificationCenter()
        let service = NotificationService(
            center: center,
            stateStore: TestNotificationStateStore(),
            preferences: preferences
        )

        await service.evaluate([makeState(resetAfter: 6 * 3_600)], now: now)

        XCTAssertTrue(center.requests.isEmpty)
    }

    func testDisablingNotificationsCancelsPendingResetRequestsOnly() async {
        let suiteName = "dev.quotapulse.tests.notifications.cancellation.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = SettingsStore(defaults: defaults)
        let center = TestUserNotificationCenter()
        center.pendingIdentifiers = [
            "quotapulse.reset.codex.primary.123.24h",
            "quotapulse.reset.claude.primary.123.6h",
            "another-app.request",
        ]
        let service = NotificationService(
            center: center,
            stateStore: TestNotificationStateStore(),
            preferences: preferences
        )
        preferences.setNotificationsEnabled(false)

        await service.preferencesDidChange()

        XCTAssertEqual(
            center.removedIdentifiers,
            [[
                "quotapulse.reset.codex.primary.123.24h",
                "quotapulse.reset.claude.primary.123.6h",
            ]]
        )
    }

    func testDisablingOneThresholdCancelsOnlyThatPendingThreshold() async {
        let suiteName = "dev.quotapulse.tests.notifications.threshold-cancellation.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = SettingsStore(defaults: defaults)
        let center = TestUserNotificationCenter()
        center.pendingIdentifiers = [
            "quotapulse.reset.codex.primary.123.long.1440m",
            "quotapulse.reset.codex.primary.123.long.360m",
        ]
        let service = NotificationService(
            center: center,
            stateStore: TestNotificationStateStore(),
            preferences: preferences
        )
        preferences.setReminder(windowClass: .long, minutes: 24 * 60, enabled: false)

        await service.preferencesDidChange()

        XCTAssertEqual(
            center.removedIdentifiers,
            [["quotapulse.reset.codex.primary.123.long.1440m"]]
        )
    }

    func testLegacyPendingThresholdIsRemovedBeforeEvaluation() async {
        let (service, center, _) = makeService()
        center.pendingIdentifiers = [
            "quotapulse.reset.codex.primary.123.6h",
            "another-app.request",
        ]

        await service.evaluate(
            [makeState(resetAfter: 5 * 3_600, duration: .seconds(5 * 3_600))],
            now: now
        )

        XCTAssertEqual(
            center.removedIdentifiers,
            [["quotapulse.reset.codex.primary.123.6h"]]
        )
        XCTAssertTrue(center.requests.isEmpty)
    }

    func testLegacyPersistedThresholdsMigrateWithoutLosingDeduplication() throws {
        let suiteName = "dev.quotapulse.tests.notifications.legacy-state.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let json = """
        {
          "schemaVersion": 1,
          "entries": [{
            "providerID": "codex",
            "windowID": "primary",
            "resetWindowIdentityMinute": 123,
            "currentResetMinute": 123,
            "emittedThresholdHours": [24, 6, 1],
            "lastObservedMinute": 100
          }]
        }
        """
        defaults.set(Data(json.utf8), forKey: "deduplication")

        let store = UserDefaultsNotificationStateStore(
            defaults: defaults,
            key: "deduplication"
        )

        XCTAssertEqual(
            store.load().entries.first?.emittedThresholdMinutes,
            [24 * 60, 6 * 60, 60]
        )
    }

    func testEligibleSnapshotRequestsUndeterminedPermissionOnce() async {
        let (service, center, _) = makeService(status: .notDetermined)

        await service.evaluate(
            [makeState(resetAfter: 6 * 3_600)],
            now: now
        )
        await service.evaluate(
            [makeState(resetAfter: 6 * 3_600)],
            now: now.addingTimeInterval(60)
        )

        XCTAssertEqual(center.authorizationRequestCount, 1)
        XCTAssertEqual(center.requests.count, 1)
    }

    func testOneProviderNotificationStateDoesNotAffectAnotherProvider() async {
        let (service, center, _) = makeService()
        let states = [
            makeState(providerID: .codex, windowID: "primary", resetAfter: 6 * 3_600),
            makeState(providerID: .claude, windowID: "five-hour", resetAfter: 6 * 3_600),
        ]

        await service.evaluate(states, now: now)
        await service.evaluate(states, now: now.addingTimeInterval(60))

        XCTAssertEqual(center.requests.count, 2)
        XCTAssertEqual(Set(center.requests.map(\.title)), [
            "Codex resets in 6 hours",
            "Claude Code resets in 6 hours",
        ])
    }

    func testTraditionalChineseNotificationFormatsThresholdAndRemainingQuota() async throws {
        let center = TestUserNotificationCenter()
        let service = NotificationService(
            center: center,
            stateStore: TestNotificationStateStore(),
            locale: Locale(identifier: "zh-Hant-TW")
        )

        await service.evaluate(
            [makeState(resetAfter: 60 * 60, duration: .seconds(5 * 3_600), usedPercentage: 39)],
            now: now
        )

        let request = try XCTUnwrap(center.requests.first)
        XCTAssertEqual(request.title, "Codex 將在 1 小時後重置")
        XCTAssertEqual(request.body, "你還有 61% 的配額尚未使用。")
    }

    func testNotificationStateRemainsBounded() {
        let policy = ResetNotificationPolicy.v01
        let states = (0..<40).map { index in
            makeState(windowID: "window-\(index)", resetAfter: 6 * 3_600)
        }

        let evaluation = policy.evaluate(
            states,
            state: NotificationDeduplicationState(),
            now: now
        )

        XCTAssertEqual(evaluation.state.entries.count, 32)
        XCTAssertEqual(evaluation.decisions.count, 32)
    }

    func testPersistedNotificationStateRespectsEncodedByteLimit() throws {
        let suiteName = "dev.quotapulse.tests.notifications.byte-limit.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let key = "notification.byte-limit"
        let store = UserDefaultsNotificationStateStore(defaults: defaults, key: key)
        let entries = (0..<2).map { index in
            NotificationDeduplicationState.Entry(
                providerID: .codex,
                windowID: "window-\(index)-" + String(repeating: "x", count: 40_000),
                resetWindowIdentityMinute: Int64(index),
                currentResetMinute: Int64(index),
                emittedThresholdMinutes: [60],
                lastObservedMinute: Int64(2 - index)
            )
        }

        store.save(NotificationDeduplicationState(entries: entries))

        let data = try XCTUnwrap(defaults.data(forKey: key))
        XCTAssertLessThanOrEqual(data.count, 64 * 1_024)
        XCTAssertEqual(store.load().entries, [entries[0]])
    }

    #if DEBUG
    func testDevelopmentNotificationRequestsAuthorizationAndSchedulesFiveSecondsAhead() async throws {
        let (service, center, _) = makeService(status: .notDetermined)

        try await service.sendTestNotification()

        XCTAssertEqual(center.authorizationRequestCount, 1)
        XCTAssertEqual(center.removedIdentifiers, [["quotapulse.test-notification"]])
        let request = try XCTUnwrap(center.requests.first)
        XCTAssertEqual(request.identifier, "quotapulse.test-notification")
        XCTAssertEqual(request.title, "QuotaPulse")
        XCTAssertEqual(request.body, "Local notifications are ready.")
        XCTAssertEqual(request.delay, 5)
    }

    func testLiveDevelopmentNotificationWhenExplicitlyEnabled() async throws {
        let isEnabled = ProcessInfo.processInfo.environment["QUOTAPULSE_RUN_LIVE_NOTIFICATION_TEST"] == "1"
            || UserDefaults.standard.bool(forKey: "runLiveNotificationTest")
        guard isEnabled else {
            throw XCTSkip("Set QUOTAPULSE_RUN_LIVE_NOTIFICATION_TEST=1 for the opt-in system notification check.")
        }

        let identifier = "quotapulse.test-notification"
        let systemCenter = UNUserNotificationCenter.current()
        systemCenter.removePendingNotificationRequests(withIdentifiers: [identifier])
        systemCenter.removeDeliveredNotifications(withIdentifiers: [identifier])
        let service = NotificationService(
            center: UserNotificationCenterClient(center: systemCenter),
            stateStore: TestNotificationStateStore()
        )

        try await service.sendTestNotification()
        try await Task.sleep(for: .seconds(6))

        let delivered = await systemCenter.deliveredNotifications()
        XCTAssertTrue(delivered.contains { $0.request.identifier == identifier })
        systemCenter.removeDeliveredNotifications(withIdentifiers: [identifier])
    }
    #endif

    private func makeService(
        status: NotificationAuthorizationStatus = .authorized
    ) -> (NotificationService, TestUserNotificationCenter, TestNotificationStateStore) {
        let center = TestUserNotificationCenter(status: status)
        let store = TestNotificationStateStore()
        return (
            NotificationService(
                center: center,
                stateStore: store,
                locale: Locale(identifier: "en")
            ),
            center,
            store
        )
    }

    private func makePreferencesWithRemindersDisabled() -> (SettingsStore, UserDefaults, String) {
        let suiteName = "dev.quotapulse.tests.local-reset-preferences.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let preferences = SettingsStore(defaults: defaults)
        disableAllReminders(in: preferences)
        return (preferences, defaults, suiteName)
    }

    private func disableAllReminders(in preferences: SettingsStore) {
        preferences.setReminder(windowClass: .short, minutes: 60, enabled: false)
        preferences.setReminder(windowClass: .short, minutes: 30, enabled: false)
        preferences.setReminder(windowClass: .long, minutes: 24 * 60, enabled: false)
        preferences.setReminder(windowClass: .long, minutes: 6 * 60, enabled: false)
        preferences.setReminder(windowClass: .long, minutes: 60, enabled: false)
    }

    private func makeState(
        providerID: ProviderID = .codex,
        status: ProviderStatus = .available,
        windowID: String = "primary",
        resetAfter: TimeInterval,
        duration: Duration = .seconds(7 * 24 * 3_600),
        usedPercentage: Double? = 39,
        capturedAt: Date? = nil
    ) -> ProviderState {
        makeState(
            providerID: providerID,
            status: status,
            windowID: windowID,
            resetAt: now.addingTimeInterval(resetAfter),
            duration: duration,
            usedPercentage: usedPercentage,
            capturedAt: capturedAt ?? now
        )
    }

    private func makeState(
        providerID: ProviderID = .codex,
        status: ProviderStatus = .available,
        windowID: String = "primary",
        resetAt: Date?,
        duration: Duration = .seconds(7 * 24 * 3_600),
        usedPercentage: Double? = 39,
        capturedAt: Date
    ) -> ProviderState {
        ProviderState(
            providerID: providerID,
            status: status,
            snapshot: ProviderUsageSnapshot(
                providerID: providerID,
                windows: [
                    UsageWindow(
                        id: windowID,
                        label: "Quota window",
                        usedPercentage: usedPercentage,
                        resetAt: resetAt,
                        duration: duration
                    )
                ],
                capturedAt: capturedAt,
                source: UsageSource(
                    kind: providerID == .codex ? .codexAppServer : .claudeStatusLineSnapshot,
                    label: "Test provider",
                    documentationURL: nil
                )
            )
        )
    }
}

@MainActor
private final class TestUserNotificationCenter: UserNotificationCentering {
    private(set) var status: NotificationAuthorizationStatus
    private(set) var authorizationRequestCount = 0
    private(set) var requests: [LocalNotificationRequest] = []
    private(set) var removedIdentifiers: [[String]] = []
    var authorizationResult = true
    var yieldsBeforeReturningAuthorizationStatus = false
    var onRequestAuthorization: (() -> Void)?
    var pendingIdentifiers: [String] = []

    init(status: NotificationAuthorizationStatus = .authorized) {
        self.status = status
    }

    func authorizationStatus() async -> NotificationAuthorizationStatus {
        if yieldsBeforeReturningAuthorizationStatus {
            await Task.yield()
        }
        return status
    }

    func requestAuthorization() async throws -> Bool {
        authorizationRequestCount += 1
        onRequestAuthorization?()
        status = authorizationResult ? .authorized : .denied
        return authorizationResult
    }

    func add(_ request: LocalNotificationRequest) async throws {
        requests.append(request)
    }

    func removePendingRequests(withIdentifiers identifiers: [String]) {
        removedIdentifiers.append(identifiers)
    }

    func pendingRequestIdentifiers() async -> [String] {
        pendingIdentifiers
    }
}

private final class TestDateSource: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date

    init(_ value: Date) {
        self.value = value
    }

    var now: Date {
        lock.withLock { value }
    }

    func advance(by interval: TimeInterval) {
        lock.withLock {
            value = value.addingTimeInterval(interval)
        }
    }
}

@MainActor
private final class SharedNotificationState {
    var state = NotificationDeduplicationState()
    var localResetState = LocalResetDetectionState()
}

@MainActor
private final class TestNotificationStateStore: NotificationStateStoring {
    private let sharedState: SharedNotificationState

    var state: NotificationDeduplicationState {
        sharedState.state
    }

    init(sharedState: SharedNotificationState = SharedNotificationState()) {
        self.sharedState = sharedState
    }

    func load() -> NotificationDeduplicationState {
        sharedState.state
    }

    func save(_ state: NotificationDeduplicationState) {
        sharedState.state = state
    }

    func loadLocalResetDetectionState() -> LocalResetDetectionState {
        sharedState.localResetState
    }

    func saveLocalResetDetectionState(_ state: LocalResetDetectionState) {
        sharedState.localResetState = state
    }
}

private actor StaticNotificationProvider: UsageProvider {
    nonisolated let id = ProviderID.codex
    private let snapshot: ProviderUsageSnapshot
    private(set) var fetchCount = 0

    init(snapshot: ProviderUsageSnapshot) {
        self.snapshot = snapshot
    }

    func fetchUsage() async throws -> ProviderUsageSnapshot {
        fetchCount += 1
        return snapshot
    }
}
