import Foundation

struct UsageWindow: Identifiable, Equatable, Sendable {
    let id: String
    let label: String
    let usedPercentage: Double?
    let resetAt: Date?
    let duration: Duration?
    let resetCycleIdentifier: String?

    init(
        id: String,
        label: String,
        usedPercentage: Double?,
        resetAt: Date?,
        duration: Duration?,
        resetCycleIdentifier: String? = nil
    ) {
        self.id = id
        self.label = label
        self.usedPercentage = usedPercentage
        self.resetAt = resetAt
        self.duration = duration
        self.resetCycleIdentifier = resetCycleIdentifier
    }

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
