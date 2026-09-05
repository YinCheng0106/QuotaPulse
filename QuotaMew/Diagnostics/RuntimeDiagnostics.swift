#if DEBUG
import Darwin
import Foundation
import OSLog

enum RuntimeRefreshSchedulerState: String, Sendable {
    case notStarted = "not_started"
    case refreshInFlight = "refresh_in_flight"
    case scheduled
    case suspendedForSleep = "suspended_for_sleep"
    case terminating
}

struct RuntimeDiagnosticsSnapshot: Equatable, Sendable {
    let memoryFootprintBytes: UInt64?
    let activeAppRefreshes: Int
    let maximumActiveAppRefreshes: Int
    let activeProviderRefreshes: Int
    let maximumActiveProviderRefreshes: Int
    let isRefreshInFlight: Bool
    let lastRefreshAttemptAt: Date?
    let lastSuccessfulRefreshAt: Date?
    let schedulerState: RuntimeRefreshSchedulerState
    let refreshSchedulerCount: Int
    let nextRefreshAt: Date?
    let consecutiveFailureCount: Int
    let codexConnectionState: String
    let codexProcessIDs: [pid_t]
    let codexStdoutReaderCount: Int
    let codexReconnectCount: Int
    let pendingNotificationCount: Int?
    let notificationDeduplicationEntryCount: Int?
    let providerAvailability: [String: String]

    func logLine(reason: String) -> String {
        let processIDs = codexProcessIDs.map(String.init).joined(separator: ",")
        let providers = providerAvailability
            .sorted { $0.key < $1.key }
            .map { "\($0.key):\($0.value)" }
            .joined(separator: ",")

        return [
            "runtime_snapshot",
            "reason=\(reason)",
            "memory_bytes=\(Self.optional(memoryFootprintBytes))",
            "app_refresh_active=\(activeAppRefreshes)",
            "app_refresh_max=\(maximumActiveAppRefreshes)",
            "provider_refresh_active=\(activeProviderRefreshes)",
            "provider_refresh_max=\(maximumActiveProviderRefreshes)",
            "refresh_in_flight=\(isRefreshInFlight)",
            "last_attempt_epoch=\(Self.epoch(lastRefreshAttemptAt))",
            "last_success_epoch=\(Self.epoch(lastSuccessfulRefreshAt))",
            "scheduler=\(schedulerState.rawValue)",
            "refresh_scheduler_count=\(refreshSchedulerCount)",
            "next_refresh_epoch=\(Self.epoch(nextRefreshAt))",
            "backoff_failures=\(consecutiveFailureCount)",
            "codex_state=\(codexConnectionState)",
            "codex_pids=\(processIDs.isEmpty ? "none" : processIDs)",
            "codex_process_count=\(codexProcessIDs.count)",
            "codex_stdout_readers=\(codexStdoutReaderCount)",
            "codex_reconnects=\(codexReconnectCount)",
            "pending_notifications=\(Self.optional(pendingNotificationCount))",
            "notification_dedup_entries=\(Self.optional(notificationDeduplicationEntryCount))",
            "providers=\(providers.isEmpty ? "none" : providers)",
        ].joined(separator: " ")
    }

    private static func optional<T>(_ value: T?) -> String {
        value.map(String.init(describing:)) ?? "unknown"
    }

    private static func epoch(_ date: Date?) -> String {
        guard let date else { return "none" }
        return String(Int64(date.timeIntervalSince1970.rounded()))
    }
}

final class RuntimeDiagnostics: @unchecked Sendable {
    static let shared = RuntimeDiagnostics()
    static let shouldLogAutomaticSnapshots =
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
    static let logsSwiftUIChanges =
        ProcessInfo.processInfo.environment["QUOTAPULSE_DEBUG_LOG_SWIFTUI_CHANGES"] == "1"

    private struct State {
        var activeAppRefreshes = 0
        var maximumActiveAppRefreshes = 0
        var activeProviderRefreshesByProvider: [ProviderID: Int] = [:]
        var maximumActiveProviderRefreshes = 0
        var lastRefreshAttemptAt: Date?
        var lastSuccessfulRefreshAt: Date?
        var schedulerState = RuntimeRefreshSchedulerState.notStarted
        var nextRefreshAt: Date?
        var consecutiveFailureCount = 0
        var codexConnectionState = "disconnected"
        var codexProcessIDs: Set<pid_t> = []
        var codexStdoutReaderProcessIDs: Set<pid_t> = []
        var hasLaunchedCodexProcess = false
        var codexReconnectCount = 0
        var pendingNotificationCount: Int?
        var notificationDeduplicationEntryCount: Int?
        var providerAvailability: [String: String] = [:]
    }

    private let lock = NSLock()
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "dev.quotapulse.app",
        category: "RuntimeDiagnostics"
    )
    private var state = State()

    func refreshStarted(at date: Date) {
        lock.withLock {
            state.activeAppRefreshes += 1
            state.maximumActiveAppRefreshes = max(
                state.maximumActiveAppRefreshes,
                state.activeAppRefreshes
            )
            state.lastRefreshAttemptAt = date
            state.schedulerState = .refreshInFlight
            state.nextRefreshAt = nil
        }
    }

    func refreshFinished(states: [ProviderState], at date: Date) {
        let availability = Dictionary(
            uniqueKeysWithValues: states.map {
                ($0.providerID.rawValue, Self.availabilityLabel(for: $0.status))
            }
        )
        lock.withLock {
            state.activeAppRefreshes = max(state.activeAppRefreshes - 1, 0)
            if states.contains(where: { $0.status == .available }) {
                state.lastSuccessfulRefreshAt = date
            }
            state.providerAvailability = availability
        }
    }

    func refreshCancelled() {
        lock.withLock {
            state.activeAppRefreshes = 0
        }
    }

    func providerRefreshStarted(_ providerID: ProviderID) {
        lock.withLock {
            state.activeProviderRefreshesByProvider[providerID, default: 0] += 1
            let activeCount = state.activeProviderRefreshesByProvider.values.reduce(0, +)
            state.maximumActiveProviderRefreshes = max(
                state.maximumActiveProviderRefreshes,
                activeCount
            )
        }
    }

    func providerRefreshFinished(_ providerID: ProviderID) {
        lock.withLock {
            let nextCount = max(
                state.activeProviderRefreshesByProvider[providerID, default: 0] - 1,
                0
            )
            if nextCount == 0 {
                state.activeProviderRefreshesByProvider.removeValue(forKey: providerID)
            } else {
                state.activeProviderRefreshesByProvider[providerID] = nextCount
            }
        }
    }

    func schedulerUpdated(
        _ schedulerState: RuntimeRefreshSchedulerState,
        nextRefreshAt: Date?,
        consecutiveFailureCount: Int
    ) {
        lock.withLock {
            state.schedulerState = schedulerState
            state.nextRefreshAt = nextRefreshAt
            state.consecutiveFailureCount = max(consecutiveFailureCount, 0)
        }
    }

    func codexProcessStarted(_ processID: pid_t) {
        lock.withLock {
            guard state.codexProcessIDs.insert(processID).inserted else { return }
            if state.hasLaunchedCodexProcess {
                state.codexReconnectCount += 1
            } else {
                state.hasLaunchedCodexProcess = true
            }
            state.codexConnectionState = "starting"
        }
    }

    func codexStdoutReaderStarted(processID: pid_t) {
        lock.withLock {
            _ = state.codexStdoutReaderProcessIDs.insert(processID)
        }
    }

    func codexConnectionBecameHealthy(processID: pid_t) {
        lock.withLock {
            state.codexConnectionState = "healthy"
            _ = state.codexProcessIDs.insert(processID)
        }
    }

    func codexConnectionStopping(processID: pid_t) {
        lock.withLock {
            guard state.codexProcessIDs.contains(processID) else { return }
            state.codexConnectionState = "stopping"
        }
    }

    func codexProcessStopped(_ processID: pid_t) {
        lock.withLock {
            _ = state.codexProcessIDs.remove(processID)
            if state.codexProcessIDs.isEmpty {
                state.codexConnectionState = "disconnected"
            }
        }
    }

    func codexStdoutReaderStopped(processID: pid_t) {
        lock.withLock {
            _ = state.codexStdoutReaderProcessIDs.remove(processID)
        }
    }

    func notificationsUpdated(pendingCount: Int, deduplicationEntryCount: Int) {
        lock.withLock {
            state.pendingNotificationCount = max(pendingCount, 0)
            state.notificationDeduplicationEntryCount = max(deduplicationEntryCount, 0)
        }
    }

    @discardableResult
    func logSnapshot(reason: String) -> RuntimeDiagnosticsSnapshot {
        let snapshot = snapshot()
        logger.info("\(snapshot.logLine(reason: reason), privacy: .public)")
        return snapshot
    }

    func snapshot() -> RuntimeDiagnosticsSnapshot {
        lock.withLock {
            RuntimeDiagnosticsSnapshot(
                memoryFootprintBytes: Self.memoryFootprintBytes(),
                activeAppRefreshes: state.activeAppRefreshes,
                maximumActiveAppRefreshes: state.maximumActiveAppRefreshes,
                activeProviderRefreshes: state.activeProviderRefreshesByProvider.values.reduce(0, +),
                maximumActiveProviderRefreshes: state.maximumActiveProviderRefreshes,
                isRefreshInFlight: state.activeAppRefreshes > 0,
                lastRefreshAttemptAt: state.lastRefreshAttemptAt,
                lastSuccessfulRefreshAt: state.lastSuccessfulRefreshAt,
                schedulerState: state.schedulerState,
                refreshSchedulerCount: state.schedulerState == .scheduled ? 1 : 0,
                nextRefreshAt: state.nextRefreshAt,
                consecutiveFailureCount: state.consecutiveFailureCount,
                codexConnectionState: state.codexConnectionState,
                codexProcessIDs: state.codexProcessIDs.sorted(),
                codexStdoutReaderCount: state.codexStdoutReaderProcessIDs.count,
                codexReconnectCount: state.codexReconnectCount,
                pendingNotificationCount: state.pendingNotificationCount,
                notificationDeduplicationEntryCount: state.notificationDeduplicationEntryCount,
                providerAvailability: state.providerAvailability
            )
        }
    }

    private static func availabilityLabel(for status: ProviderStatus) -> String {
        switch status {
        case .loading: "loading"
        case .available: "available"
        case .stale: "stale"
        case .disabled: "disabled"
        case .notConfigured: "not_configured"
        case .notInstalled: "not_installed"
        case .unsupportedAuthentication: "unsupported_authentication"
        case .failed: "failed"
        }
    }

    private static func memoryFootprintBytes() -> UInt64? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return info.phys_footprint
    }
}
#endif
