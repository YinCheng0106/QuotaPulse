import Foundation

struct UsageWindow: Identifiable, Equatable, Sendable {
    let id: String
    let label: String
    let usedPercentage: Double?
    let resetAt: Date?
    let duration: Duration?

    var displayUsedPercentage: Double? {
        guard let usedPercentage, usedPercentage.isFinite else { return nil }
        return min(max(usedPercentage, 0), 100)
    }

    var remainingPercentage: Double? {
        displayUsedPercentage.map { 100 - $0 }
    }

    var progress: Double? {
        displayUsedPercentage.map { $0 / 100 }
    }
}
