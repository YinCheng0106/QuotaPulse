import Foundation
import XCTest
@testable import QuotaPulse

final class ResetEventTests: XCTestCase {
    func testValidFixturesDecode() throws {
        for name in ["01-global-announcement", "02-global-completed", "03-banked-reset", "04-temporary-increase", "05-effective-range", "06-second-revision", "07-correction", "08-retraction", "09-audience-restricted", "10-multiple-providers", "20-minimal"] {
            _ = try decodeFixture(named: name)
        }
    }

    func testFeedRoundTripPreservesStableIdentityAndRevision() throws {
        let feed = try decodeFixture(named: "06-second-revision")
        let decoded = try ResetEventFeed.decode(from: ResetEventFeed.encode(feed))
        XCTAssertEqual(decoded, feed)
        XCTAssertEqual(decoded.events.first?.id, "codex.global-reset-2026-01")
        XCTAssertEqual(decoded.events.first?.revision, 2)
        XCTAssertEqual(decoded.events.first?.publisher, "OpenAI Status")
    }

    func testCorrectionAndRetractionReferenceDirectOriginalEvent() throws {
        let correction = try decodeFixture(named: "07-correction")
        let retraction = try decodeFixture(named: "08-retraction")
        XCTAssertEqual(correction.events.last?.correctsEventID, "codex.global-reset-2026-01")
        XCTAssertNil(correction.events.last?.retractsEventID)
        XCTAssertEqual(retraction.events.last?.retractsEventID, "codex.banked-reset-2026-01")
        XCTAssertNil(retraction.events.last?.correctsEventID)
        XCTAssertEqual(correction.activeEvents.map(\.id), ["codex.correction-2026-01"])
        XCTAssertTrue(retraction.activeEvents.isEmpty)
    }

    func testInvalidFixturesRejectEntireFeed() {
        for name in ["11-malformed-timestamp", "12-malformed-url", "13-duplicate-id", "15-future-schema", "16-oversized-summary", "17-excessive-event-count", "18-invalid-correction-target", "19-invalid-retraction-target"] {
            XCTAssertThrowsError(try decodeFixture(named: name), name)
        }
    }

    func testRevisionRegressionIsRejectedAgainstLastKnownGoodFeed() throws {
        let latest = try decodeFixture(named: "06-second-revision")
        let regressed = try decodeFixture(named: "14-revision-regression")
        XCTAssertThrowsError(try regressed.validate(against: latest)) { error in
            XCTAssertEqual(error as? ResetEventFeedValidationError, .revisionRegression(eventID: "codex.global-reset-2026-01"))
        }
    }

    func testEventCountBoundRejectsBeforeDecodingUnboundedEntries() {
        XCTAssertThrowsError(try decodeFixture(named: "17-excessive-event-count")) { error in
            XCTAssertEqual(error as? ResetEventFeedValidationError, .tooManyEvents)
        }
    }

    func testUnknownEventKindIsExplicitlyRejected() throws {
        var object = try JSONSerialization.jsonObject(with: fixtureData(named: "20-minimal")) as! [String: Any]
        var events = object["events"] as! [[String: Any]]
        events[0]["kind"] = "futureResetKind"
        object["events"] = events
        let data = try JSONSerialization.data(withJSONObject: object)
        XCTAssertThrowsError(try ResetEventFeed.decode(from: data)) { error in
            XCTAssertEqual(error as? ResetEventFeedValidationError, .unknownEventKind("futureResetKind"))
        }
    }

    func testUnknownProviderIsRejected() throws {
        var object = try JSONSerialization.jsonObject(with: fixtureData(named: "20-minimal")) as! [String: Any]
        var events = object["events"] as! [[String: Any]]
        events[0]["providerID"] = "future-provider"
        object["events"] = events
        let data = try JSONSerialization.data(withJSONObject: object)
        XCTAssertThrowsError(try ResetEventFeed.decode(from: data))
    }

    func testSourceAbstractionReturnsProviderIndependentEvents() async throws {
        let events = try decodeFixture(named: "10-multiple-providers").events
        let fetched = try await FixtureResetEventSource(events: events).fetchEvents()
        XCTAssertEqual(fetched, events)
    }

    private func decodeFixture(named name: String) throws -> ResetEventFeed {
        try ResetEventFeed.decode(from: fixtureData(named: name))
    }

    private func fixtureData(named name: String) -> Data {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/ResetIntelligenceFeed/\(name).json")
        return try! Data(contentsOf: sourceURL)
    }
}

private struct FixtureResetEventSource: ResetEventSource {
    let events: [ResetEvent]
    func fetchEvents() async throws -> [ResetEvent] { events }
}
