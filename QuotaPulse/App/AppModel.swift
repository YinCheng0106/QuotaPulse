import AppKit
import Foundation
import Observation

@Observable
@MainActor
final class AppModel {
    private(set) var providerStates: [ProviderState]
    private(set) var isRefreshing = false
    private(set) var lastUpdatedAt: Date?

    #if DEBUG
    private(set) var notificationFeedback: String?
    private(set) var runtimeDiagnosticsFeedback: String?
    #endif

    @ObservationIgnored private let refreshCoordinator: RefreshCoordinator
    @ObservationIgnored private let notificationService: any NotificationServicing
    @ObservationIgnored private let refreshPolicy: RefreshPolicy
    @ObservationIgnored private let refreshSleeper: any RefreshSleeping
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let diagnosticEnvironment: CompatibilityDiagnosticEnvironment
    @ObservationIgnored private let lifecycleObservers: AppLifecycleObserverBag
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var scheduledRefreshTask: Task<Void, Never>?
    @ObservationIgnored private var coordinatorCancellationTask: Task<Void, Never>?
    @ObservationIgnored private var refreshAfterCurrentCompletes = false
    @ObservationIgnored private var lastRefreshAttemptAt: Date?

    private var didStart = false
    private var isSleeping = false
    private var isTerminating = false
    private var refreshGeneration: UInt64 = 0
    private var scheduleGeneration: UInt64 = 0
    private var consecutiveFailureCount = 0
    private var lastRefreshCompletedAt: Date?
    private var nextRefreshAt: Date?

    init(
        providerIDs: [ProviderID],
        refreshCoordinator: RefreshCoordinator,
        notificationService: any NotificationServicing,
        refreshPolicy: RefreshPolicy = .v01,
        refreshSleeper: any RefreshSleeping = ContinuousRefreshSleeper(),
        now: @escaping @Sendable () -> Date = Date.init,
        diagnosticEnvironment: CompatibilityDiagnosticEnvironment = .current(),
        applicationNotificationCenter: NotificationCenter = .default,
        workspaceNotificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        observesLifecycle: Bool = true
    ) {
        self.providerStates = providerIDs.map { ProviderState.loading($0) }
        self.refreshCoordinator = refreshCoordinator
        self.notificationService = notificationService
        self.refreshPolicy = refreshPolicy
        self.refreshSleeper = refreshSleeper
        self.now = now
        self.diagnosticEnvironment = diagnosticEnvironment
        self.lifecycleObservers = AppLifecycleObserverBag(
            applicationNotificationCenter: applicationNotificationCenter,
            workspaceNotificationCenter: workspaceNotificationCenter
        )

        if observesLifecycle {
            installLifecycleObservers()
        }
    }

    deinit {
        refreshTask?.cancel()
        scheduledRefreshTask?.cancel()
        coordinatorCancellationTask?.cancel()
    }

    func start() {
        guard !didStart, !isTerminating else { return }
        didStart = true
        requestRefresh()
    }

    func menuDidOpen() {
        guard didStart else {
            start()
            return
        }

        let currentDate = now()
        if consecutiveFailureCount > 0, let nextRefreshAt, currentDate < nextRefreshAt {
            return
        }
        if let lastRefreshCompletedAt,
           currentDate.timeIntervalSince(lastRefreshCompletedAt) < refreshPolicy.menuStaleThreshold {
            return
        }
        let hasStaleSnapshot = providerStates.contains { state in
            guard let capturedAt = state.snapshot?.capturedAt else { return false }
            return currentDate.timeIntervalSince(capturedAt) >= refreshPolicy.menuStaleThreshold
        }

        if hasStaleSnapshot {
            requestRefresh()
        }
    }

    func refreshManually() {
        guard !isTerminating else { return }
        if !didStart {
            didStart = true
        }
        requestRefresh()
    }

    func providerPreferencesDidChange() {
        guard !isTerminating else { return }
        if refreshTask != nil {
            refreshAfterCurrentCompletes = true
        } else {
            refreshManually()
        }
    }

    func refresh() async {
        refreshManually()
        await refreshTask?.value
    }

    func compatibilityDiagnostics() async -> CompatibilityDiagnosticsSnapshot {
        let contexts = await refreshCoordinator.providerDiagnostics()
        return CompatibilityDiagnosticsSnapshot(
            environment: diagnosticEnvironment,
            providerStates: providerStates,
            providerContexts: contexts,
            lastRefreshAttemptAt: lastRefreshAttemptAt
        )
    }

    func applicationDidBecomeActive() {
        guard !isTerminating else { return }
        guard didStart else {
            start()
            return
        }
        resumeScheduleIfNeeded()
    }

    func systemWillSleep() {
        guard !isTerminating else { return }
        isSleeping = true
        cancelScheduledRefresh(clearDeadline: false)
        #if DEBUG
        RuntimeDiagnostics.shared.schedulerUpdated(
            .suspendedForSleep,
            nextRefreshAt: nextRefreshAt,
            consecutiveFailureCount: consecutiveFailureCount
        )
        #endif
    }

    func systemDidWake() {
        guard !isTerminating else { return }
        isSleeping = false
        guard didStart else {
            start()
            return
        }
        resumeScheduleIfNeeded()
    }

    private func requestRefresh() {
        guard refreshTask == nil, !isSleeping, !isTerminating else { return }

        cancelScheduledRefresh(clearDeadline: true)
        isRefreshing = true
        lastRefreshAttemptAt = now()
        #if DEBUG
        RuntimeDiagnostics.shared.refreshStarted(at: lastRefreshAttemptAt ?? now())
        if RuntimeDiagnostics.shouldLogAutomaticSnapshots {
            RuntimeDiagnostics.shared.logSnapshot(reason: "refresh_started")
        }
        #endif

        let loadingStates = providerStates.map {
            ProviderState.loading($0.providerID, snapshot: $0.snapshot)
        }
        if providerStates != loadingStates {
            providerStates = loadingStates
        }

        refreshGeneration &+= 1
        let generation = refreshGeneration
        let refreshCoordinator = refreshCoordinator
        refreshTask = Task { [weak self] in
            let states = await refreshCoordinator.refresh()
            guard let self else { return }
            guard self.finishRefresh(states, generation: generation) else { return }
            let evaluationDate = self.now()
            await self.notificationService.evaluate(states, now: evaluationDate)
            if self.refreshAfterCurrentCompletes {
                self.refreshAfterCurrentCompletes = false
                self.refreshManually()
            }
        }
    }

    private func finishRefresh(_ states: [ProviderState], generation: UInt64) -> Bool {
        guard generation == refreshGeneration else { return false }

        refreshTask = nil
        isRefreshing = false
        let completedAt = now()
        lastRefreshCompletedAt = completedAt
        let cachedSnapshots = Dictionary(
            uniqueKeysWithValues: providerStates.compactMap { state in
                state.snapshot.map { (state.providerID, $0) }
            }
        )
        let displayStates = states.map { state in
            guard state.snapshot == nil,
                  let cachedSnapshot = cachedSnapshots[state.providerID]
            else {
                return state
            }

            switch state.status {
            case .disabled, .failed:
                break
            default:
                return state
            }

            return ProviderState(
                providerID: state.providerID,
                status: state.status,
                snapshot: cachedSnapshot
            )
        }
        if providerStates != displayStates {
            providerStates = displayStates
        }
        lastUpdatedAt = displayStates.compactMap(\.lastUpdatedAt).max()

        if refreshPolicy.hasRetryableFailure(in: states) {
            consecutiveFailureCount += 1
        } else {
            consecutiveFailureCount = 0
        }

        let delay = refreshPolicy.nextRefreshDelay(
            consecutiveFailureCount: consecutiveFailureCount
        )
        scheduleRefresh(after: delay)
        #if DEBUG
        RuntimeDiagnostics.shared.refreshFinished(states: states, at: completedAt)
        if RuntimeDiagnostics.shouldLogAutomaticSnapshots {
            RuntimeDiagnostics.shared.logSnapshot(reason: "refresh_completed")
        }
        #endif
        return true
    }

    private func scheduleRefresh(after delay: TimeInterval) {
        let deadline = now().addingTimeInterval(max(delay, 0))
        nextRefreshAt = deadline

        #if DEBUG
        RuntimeDiagnostics.shared.schedulerUpdated(
            isSleeping ? .suspendedForSleep : .scheduled,
            nextRefreshAt: deadline,
            consecutiveFailureCount: consecutiveFailureCount
        )
        #endif

        guard !isSleeping, !isTerminating else { return }
        installScheduledRefresh(deadline: deadline)
    }

    private func installScheduledRefresh(deadline: Date) {
        cancelScheduledRefresh(clearDeadline: false)

        scheduleGeneration &+= 1
        let generation = scheduleGeneration
        let delay = max(deadline.timeIntervalSince(now()), 0)
        let refreshSleeper = refreshSleeper
        scheduledRefreshTask = Task { [weak self] in
            do {
                try await refreshSleeper.sleep(for: .seconds(delay))
            } catch {
                return
            }

            guard let self else { return }
            self.scheduledRefreshDidFire(generation: generation)
        }
    }

    private func scheduledRefreshDidFire(generation: UInt64) {
        guard generation == scheduleGeneration, !isSleeping, !isTerminating else { return }
        scheduledRefreshTask = nil
        nextRefreshAt = nil
        requestRefresh()
    }

    private func resumeScheduleIfNeeded() {
        guard refreshTask == nil, scheduledRefreshTask == nil, !isSleeping else { return }

        guard let nextRefreshAt else {
            scheduleRefresh(after: refreshPolicy.normalBackgroundInterval)
            return
        }

        if nextRefreshAt <= now() {
            requestRefresh()
        } else {
            installScheduledRefresh(deadline: nextRefreshAt)
        }
    }

    private func cancelScheduledRefresh(clearDeadline: Bool) {
        scheduledRefreshTask?.cancel()
        scheduledRefreshTask = nil
        scheduleGeneration &+= 1
        if clearDeadline {
            nextRefreshAt = nil
        }
    }

    private func terminate() {
        guard !isTerminating else { return }
        isTerminating = true
        cancelScheduledRefresh(clearDeadline: true)
        refreshTask?.cancel()
        refreshTask = nil
        isRefreshing = false

        #if DEBUG
        RuntimeDiagnostics.shared.refreshCancelled()
        RuntimeDiagnostics.shared.schedulerUpdated(
            .terminating,
            nextRefreshAt: nil,
            consecutiveFailureCount: consecutiveFailureCount
        )
        #endif

        let refreshCoordinator = refreshCoordinator
        coordinatorCancellationTask = Task {
            await refreshCoordinator.cancel()
        }
    }

    private func installLifecycleObservers() {
        lifecycleObservers.observeApplication(
            name: NSApplication.didBecomeActiveNotification
        ) { [weak self] in
            Task { @MainActor [weak self] in
                self?.applicationDidBecomeActive()
            }
        }
        lifecycleObservers.observeApplication(
            name: NSApplication.willTerminateNotification
        ) { [weak self] in
            Task { @MainActor [weak self] in
                self?.terminate()
            }
        }
        lifecycleObservers.observeWorkspace(
            name: NSWorkspace.willSleepNotification
        ) { [weak self] in
            Task { @MainActor [weak self] in
                self?.systemWillSleep()
            }
        }
        lifecycleObservers.observeWorkspace(
            name: NSWorkspace.didWakeNotification
        ) { [weak self] in
            Task { @MainActor [weak self] in
                self?.systemDidWake()
            }
        }
    }

    #if DEBUG
    func sendTestNotification() async {
        do {
            try await notificationService.sendTestNotification()
            notificationFeedback = String(localized: "Test notification scheduled for about 5 seconds from now.")
        } catch {
            notificationFeedback = String(localized: "Notifications are unavailable.")
        }
    }

    func logRuntimeDiagnosticsSnapshot() async {
        await notificationService.updateRuntimeDiagnostics()
        RuntimeDiagnostics.shared.logSnapshot(reason: "manual_checkpoint")
        runtimeDiagnosticsFeedback = String(localized: "Runtime snapshot written to Console.")
    }
    #endif
}

private final class AppLifecycleObserverBag: @unchecked Sendable {
    private let applicationNotificationCenter: NotificationCenter
    private let workspaceNotificationCenter: NotificationCenter
    private var applicationObservers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []

    init(
        applicationNotificationCenter: NotificationCenter,
        workspaceNotificationCenter: NotificationCenter
    ) {
        self.applicationNotificationCenter = applicationNotificationCenter
        self.workspaceNotificationCenter = workspaceNotificationCenter
    }

    deinit {
        applicationObservers.forEach(applicationNotificationCenter.removeObserver)
        workspaceObservers.forEach(workspaceNotificationCenter.removeObserver)
    }

    func observeApplication(
        name: Notification.Name,
        action: @escaping @Sendable () -> Void
    ) {
        applicationObservers.append(
            applicationNotificationCenter.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { _ in
                action()
            }
        )
    }

    func observeWorkspace(
        name: Notification.Name,
        action: @escaping @Sendable () -> Void
    ) {
        workspaceObservers.append(
            workspaceNotificationCenter.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { _ in
                action()
            }
        )
    }
}
