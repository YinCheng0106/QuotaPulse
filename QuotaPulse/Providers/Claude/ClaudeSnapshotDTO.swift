import Foundation

struct ClaudeUsageSnapshotDocument: Decodable, Equatable, Sendable {
    let schemaVersion: Int
    let capturedAt: Date
    let claudeCodeVersion: String?
    let rateLimits: ClaudeRateLimits
}

struct ClaudeRateLimits: Decodable, Equatable, Sendable {
    let fiveHour: ClaudeRateLimitWindow?
    let sevenDay: ClaudeRateLimitWindow?
}

struct ClaudeRateLimitWindow: Decodable, Equatable, Sendable {
    let usedPercentage: Double?
    let resetsAt: TimeInterval?
}
