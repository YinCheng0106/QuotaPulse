import Foundation

struct RefreshPolicy: Equatable, Sendable {
    static let v01 = RefreshPolicy(
        normalBackgroundInterval: 15 * 60,
        menuStaleThreshold: 3 * 60,
        failureRetryIntervals: [60, 2 * 60, 5 * 60, 15 * 60, 30 * 60]
    )

    let normalBackgroundInterval: TimeInterval
    let menuStaleThreshold: TimeInterval
    let failureRetryIntervals: [TimeInterval]

    func nextRefreshDelay(consecutiveFailureCount: Int) -> TimeInterval {
        guard consecutiveFailureCount > 0, !failureRetryIntervals.isEmpty else {
            return normalBackgroundInterval
        }

        let index = min(consecutiveFailureCount - 1, failureRetryIntervals.count - 1)
        return failureRetryIntervals[index]
    }

    func hasRetryableFailure(in states: [ProviderState]) -> Bool {
        states.contains { state in
            if case .failed = state.status {
                return true
            }
            return false
        }
    }
}

protocol RefreshSleeping: Sendable {
    func sleep(for duration: Duration) async throws
}

struct ContinuousRefreshSleeper: RefreshSleeping {
    private let tolerance: Duration

    init(tolerance: Duration = .seconds(30)) {
        self.tolerance = tolerance
    }

    func sleep(for duration: Duration) async throws {
        try await ContinuousClock().sleep(for: duration, tolerance: tolerance)
    }
}
