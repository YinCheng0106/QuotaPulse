import Foundation
import XCTest
@testable import QuotaPulse

final class ResetEventTests: XCTestCase {
    func testCodableRoundTripPreservesTrustedSource() throws {
        let event = makeEvent(kind: .globalResetAnnounced)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        let data = try encoder.encode(event)
        let decoded = try JSONDecoder().decode(ResetEvent.self, from: data)

        XCTAssertEqual(decoded, event)
        XCTAssertEqual(decoded.sourceName, "OpenAI Status")
        XCTAssertEqual(decoded.sourceURL.absoluteString, "https://status.openai.com/example")
    }

    func testKindsRemainDistinctAfterCoding() throws {
        let kinds = ResetEventKind.allCases
        let events = kinds.map { makeEvent(kind: $0) }

        let data = try JSONEncoder().encode(events)
        let decoded = try JSONDecoder().decode([ResetEvent].self, from: data)

        XCTAssertEqual(decoded.map(\.kind), kinds)
        XCTAssertEqual(Set(decoded.map(\.kind.rawValue)).count, kinds.count)
    }

    func testSourceAbstractionReturnsProviderIndependentEvents() async throws {
        let events = [
            makeEvent(kind: .globalResetCompleted, providerID: .codex),
            makeEvent(kind: .bankedResetGranted, providerID: .claude),
        ]
        let source = FixtureResetEventSource(events: events)

        let fetched = try await source.fetchEvents()

        XCTAssertEqual(fetched, events)
    }

    private func makeEvent(
        kind: ResetEventKind,
        providerID: ProviderID = .codex
    ) -> ResetEvent {
        ResetEvent(
            id: "\(providerID.rawValue).\(kind.rawValue)",
            providerID: providerID,
            kind: kind,
            publishedAt: Date(timeIntervalSince1970: 2_000_000_000),
            effectiveAt: Date(timeIntervalSince1970: 2_000_000_060),
            expiresAt: Date(timeIntervalSince1970: 2_000_003_600),
            audience: .eligibleSubscribers,
            sourceName: "OpenAI Status",
            sourceURL: URL(string: "https://status.openai.com/example")!,
            displaySummary: "A verified reset is available.",
            displaySummaryLocaleIdentifier: "en"
        )
    }
}

private struct FixtureResetEventSource: ResetEventSource {
    let events: [ResetEvent]

    func fetchEvents() async throws -> [ResetEvent] {
        events
    }
}
