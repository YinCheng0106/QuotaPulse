import Foundation

struct CodexRateLimitsResult: Decodable, Equatable, Sendable {
    let rateLimits: CodexRateLimitBucket?
    let rateLimitsByLimitId: [String: CodexRateLimitBucket]?
}

struct CodexRateLimitBucket: Decodable, Equatable, Sendable {
    let limitId: String?
    let limitName: String?
    let primary: CodexRateLimitWindow?
    let secondary: CodexRateLimitWindow?
}

struct CodexRateLimitWindow: Decodable, Equatable, Sendable {
    let usedPercent: Double?
    let windowDurationMins: Int?
    let resetsAt: TimeInterval?
}
