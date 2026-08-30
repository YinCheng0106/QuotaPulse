import Foundation

enum ResetEventKind: String, Codable, CaseIterable, Sendable {
    case scheduledResetObserved
    case globalResetAnnounced
    case globalResetCompleted
    case bankedResetGranted
}

enum ResetEventAudience: String, Codable, CaseIterable, Sendable {
    case allUsers
    case eligibleSubscribers
    case affectedAccounts
    case unspecified
}

struct ResetEvent: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let providerID: ProviderID
    let kind: ResetEventKind
    let publishedAt: Date
    let effectiveAt: Date?
    let expiresAt: Date?
    let audience: ResetEventAudience
    let sourceName: String
    let sourceURL: URL
    let displaySummary: String
    let displaySummaryLocaleIdentifier: String?
}

protocol ResetEventSource: Sendable {
    func fetchEvents() async throws -> [ResetEvent]
}
