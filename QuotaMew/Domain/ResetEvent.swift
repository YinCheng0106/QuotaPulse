import Foundation

/// An externally published Reset Intelligence event. This is deliberately separate
/// from `DetectedQuotaReset`, which is evidence observed only on this Mac.
enum ResetEventKind: Equatable, Sendable, Codable, CaseIterable {
    case globalResetAnnounced
    case globalResetCompleted
    case bankedResetGranted
    case temporaryQuotaIncrease
    case resetExpected
    case correction
    case retraction
    case unknown(String)

    static var allCases: [ResetEventKind] {
        [.globalResetAnnounced, .globalResetCompleted, .bankedResetGranted,
         .temporaryQuotaIncrease, .resetExpected, .correction, .retraction]
    }

    var rawValue: String {
        switch self {
        case .globalResetAnnounced: "globalResetAnnounced"
        case .globalResetCompleted: "globalResetCompleted"
        case .bankedResetGranted: "bankedResetGranted"
        case .temporaryQuotaIncrease: "temporaryQuotaIncrease"
        case .resetExpected: "resetExpected"
        case .correction: "correction"
        case .retraction: "retraction"
        case let .unknown(value): value
        }
    }

    init(from decoder: any Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        switch value {
        case "globalResetAnnounced": self = .globalResetAnnounced
        case "globalResetCompleted": self = .globalResetCompleted
        case "bankedResetGranted": self = .bankedResetGranted
        case "temporaryQuotaIncrease": self = .temporaryQuotaIncrease
        case "resetExpected": self = .resetExpected
        case "correction": self = .correction
        case "retraction": self = .retraction
        default: self = .unknown(value)
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

enum ResetEventVerification: String, Codable, CaseIterable, Sendable {
    case official
    case trustedPublisher
    case unverified
}

enum ResetEventAudience: Equatable, Sendable, Codable {
    case allUsers
    case paidUsers
    case planFamilies([String])
    case unspecified

    private enum CodingKeys: String, CodingKey { case kind, planFamilies }
    private enum Kind: String, Codable { case allUsers, paidUsers, planFamilies, unspecified }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .allUsers: self = .allUsers
        case .paidUsers: self = .paidUsers
        case .unspecified: self = .unspecified
        case .planFamilies:
            self = .planFamilies(try container.decode([String].self, forKey: .planFamilies))
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .allUsers: try container.encode(Kind.allUsers, forKey: .kind)
        case .paidUsers: try container.encode(Kind.paidUsers, forKey: .kind)
        case let .planFamilies(families):
            try container.encode(Kind.planFamilies, forKey: .kind)
            try container.encode(families, forKey: .planFamilies)
        case .unspecified: try container.encode(Kind.unspecified, forKey: .kind)
        }
    }
}

struct ResetEvent: Identifiable, Codable, Equatable, Sendable {
    /// Stable logical-event identity. It never changes when the representation is revised.
    let id: String
    /// Monotonically increasing representation of `id`; only the latest revision is in a feed.
    let revision: Int
    let providerID: ProviderID
    let kind: ResetEventKind
    let publisher: String
    let sourceURL: URL
    let publishedAt: Date
    let retrievedAt: Date
    let effectiveAt: Date?
    let effectiveUntil: Date?
    let expiresAt: Date?
    let audience: ResetEventAudience
    let verification: ResetEventVerification
    let displaySummary: String
    let displaySummaryLocaleIdentifier: String?
    /// The original logical event replaced by this correction. Only valid for `.correction`.
    let correctsEventID: String?
    /// The original logical event withdrawn by this retraction. Only valid for `.retraction`.
    let retractsEventID: String?
}

struct ResetEventFeed: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1
    static let maximumResponseBytes = 256 * 1_024
    static let maximumEventCount = 128
    static let maximumIDBytes = 128
    static let maximumRevision = 1_000_000_000
    static let maximumPublisherBytes = 120
    static let maximumSummaryBytes = 500
    static let maximumURLBytes = 2_048
    static let maximumLocaleIdentifierBytes = 35
    static let maximumPlanFamilies = 8
    static let maximumPlanFamilyBytes = 64

    let schemaVersion: Int
    let generatedAt: Date
    let events: [ResetEvent]

    init(schemaVersion: Int = currentSchemaVersion, generatedAt: Date, events: [ResetEvent]) throws {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.events = events
        try validate()
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        let generatedAt = try container.decode(Date.self, forKey: .generatedAt)
        let eventContainer = try container.nestedUnkeyedContainer(forKey: .events)
        if let count = eventContainer.count, count > Self.maximumEventCount {
            throw ResetEventFeedValidationError.tooManyEvents
        }
        let events = try container.decode([ResetEvent].self, forKey: .events)
        try self.init(schemaVersion: schemaVersion, generatedAt: generatedAt, events: events)
    }

    static func decode(from data: Data) throws -> ResetEventFeed {
        guard data.count <= maximumResponseBytes else { throw ResetEventFeedValidationError.responseTooLarge }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Self.self, from: data)
    }

    static func encode(_ feed: ResetEventFeed) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(feed)
    }

    /// Validates a newly received full snapshot against an earlier accepted snapshot.
    /// Same ID/revision must be equivalent; a lower revision is rejected.
    func validate(against previous: ResetEventFeed) throws {
        try validate()
        let priorEvents = Dictionary(uniqueKeysWithValues: previous.events.map { ($0.id, $0) })
        for event in events {
            guard let prior = priorEvents[event.id] else { continue }
            if event.revision < prior.revision {
                throw ResetEventFeedValidationError.revisionRegression(eventID: event.id)
            }
            if event.revision == prior.revision, event != prior {
                throw ResetEventFeedValidationError.conflictingRevision(eventID: event.id)
            }
        }
    }

    func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw ResetEventFeedValidationError.unsupportedSchemaVersion(schemaVersion)
        }
        guard isFinite(generatedAt) else { throw ResetEventFeedValidationError.invalidTimestamp }
        guard events.count <= Self.maximumEventCount else { throw ResetEventFeedValidationError.tooManyEvents }

        var eventByID: [String: ResetEvent] = [:]
        for event in events {
            guard eventByID[event.id] == nil else { throw ResetEventFeedValidationError.duplicateEventID(event.id) }
            try validate(event)
            eventByID[event.id] = event
        }

        for event in events where event.correctsEventID != nil || event.retractsEventID != nil {
            let targetID = event.correctsEventID ?? event.retractsEventID!
            guard targetID != event.id, let target = eventByID[targetID],
                  target.providerID == event.providerID,
                  target.correctsEventID == nil,
                  target.retractsEventID == nil else {
                throw ResetEventFeedValidationError.invalidRelationship(eventID: event.id)
            }
        }
    }

    /// The deterministic future-presentation projection for this complete snapshot.
    /// A newer revision is already the sole representation of an ID; a correction
    /// replaces its direct original, while a retraction hides its original and any
    /// direct correction notice. Retractions remain available in the raw feed for
    /// future audit/history handling but are not active user-facing events.
    var activeEvents: [ResetEvent] {
        let correctedIDs = Set(events.compactMap(\.correctsEventID))
        let retractedIDs = Set(events.compactMap(\.retractsEventID))
        return events.filter { event in
            switch event.kind {
            case .retraction:
                return false
            case .correction:
                guard let targetID = event.correctsEventID else { return false }
                return !retractedIDs.contains(targetID)
            default:
                return !correctedIDs.contains(event.id) && !retractedIDs.contains(event.id)
            }
        }
    }

    private func validate(_ event: ResetEvent) throws {
        guard event.revision > 0, event.revision <= Self.maximumRevision else {
            throw ResetEventFeedValidationError.invalidRevision(eventID: event.id)
        }
        guard isStableID(event.id) else { throw ResetEventFeedValidationError.invalidEventID(event.id) }
        if case .unknown = event.kind { throw ResetEventFeedValidationError.unknownEventKind(event.kind.rawValue) }
        guard isFinite(event.publishedAt), isFinite(event.retrievedAt),
              event.retrievedAt >= event.publishedAt else { throw ResetEventFeedValidationError.invalidTimestamp }
        if let effectiveAt = event.effectiveAt, !isFinite(effectiveAt) { throw ResetEventFeedValidationError.invalidTimestamp }
        if let effectiveUntil = event.effectiveUntil {
            guard isFinite(effectiveUntil), let effectiveAt = event.effectiveAt, effectiveUntil >= effectiveAt else {
                throw ResetEventFeedValidationError.invalidTimeRange
            }
        }
        if let expiresAt = event.expiresAt, !isFinite(expiresAt) { throw ResetEventFeedValidationError.invalidTimestamp }
        guard validHTTPSURL(event.sourceURL), byteCount(event.sourceURL.absoluteString) <= Self.maximumURLBytes else {
            throw ResetEventFeedValidationError.invalidSourceURL
        }
        guard nonEmpty(event.publisher, maximum: Self.maximumPublisherBytes),
              nonEmpty(event.displaySummary, maximum: Self.maximumSummaryBytes),
              optionalStringIsValid(event.displaySummaryLocaleIdentifier, maximum: Self.maximumLocaleIdentifierBytes) else {
            throw ResetEventFeedValidationError.oversizedOrEmptyField
        }
        if case let .planFamilies(families) = event.audience {
            guard !families.isEmpty, families.count <= Self.maximumPlanFamilies,
                  families.allSatisfy({ nonEmpty($0, maximum: Self.maximumPlanFamilyBytes) }) else {
                throw ResetEventFeedValidationError.invalidAudience
            }
        }
        switch event.kind {
        case .correction:
            guard event.correctsEventID != nil, event.retractsEventID == nil else {
                throw ResetEventFeedValidationError.invalidRelationship(eventID: event.id)
            }
        case .retraction:
            guard event.retractsEventID != nil, event.correctsEventID == nil else {
                throw ResetEventFeedValidationError.invalidRelationship(eventID: event.id)
            }
        default:
            guard event.correctsEventID == nil, event.retractsEventID == nil else {
                throw ResetEventFeedValidationError.invalidRelationship(eventID: event.id)
            }
        }
    }

    private func isStableID(_ value: String) -> Bool {
        guard nonEmpty(value, maximum: Self.maximumIDBytes), let first = value.utf8.first else { return false }
        guard (first >= 97 && first <= 122) || (first >= 48 && first <= 57) else { return false }
        return value.utf8.allSatisfy { byte in
            (byte >= 97 && byte <= 122) || (byte >= 48 && byte <= 57) || byte == 45 || byte == 46 || byte == 95
        }
    }

    private func validHTTPSURL(_ url: URL) -> Bool { url.scheme?.lowercased() == "https" && url.host?.isEmpty == false }
    private func isFinite(_ date: Date) -> Bool { date.timeIntervalSinceReferenceDate.isFinite }
    private func nonEmpty(_ value: String, maximum: Int) -> Bool { !value.isEmpty && byteCount(value) <= maximum }
    private func optionalStringIsValid(_ value: String?, maximum: Int) -> Bool { value.map { !$0.isEmpty && byteCount($0) <= maximum } ?? true }
    private func byteCount(_ value: String) -> Int { value.lengthOfBytes(using: .utf8) }
}

enum ResetEventFeedValidationError: Error, Equatable, Sendable {
    case responseTooLarge
    case unsupportedSchemaVersion(Int)
    case tooManyEvents
    case invalidTimestamp
    case invalidTimeRange
    case invalidSourceURL
    case invalidEventID(String)
    case duplicateEventID(String)
    case invalidRevision(eventID: String)
    case revisionRegression(eventID: String)
    case conflictingRevision(eventID: String)
    case unknownEventKind(String)
    case invalidRelationship(eventID: String)
    case invalidAudience
    case oversizedOrEmptyField
}

protocol ResetEventSource: Sendable {
    func fetchEvents() async throws -> [ResetEvent]
}
