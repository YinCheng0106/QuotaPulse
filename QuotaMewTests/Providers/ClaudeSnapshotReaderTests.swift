import Foundation
import Darwin
import XCTest
@testable import QuotaMew

final class ClaudeSnapshotReaderTests: XCTestCase {
    func testReadsVersionedMinimalSnapshotAndIgnoresUnknownFields() async throws {
        let fileURL = temporaryFileURL()
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let data = Data(#"{"schemaVersion":1,"capturedAt":"2033-05-18T03:33:20Z","claudeCodeVersion":"2.1.80","rateLimits":{"fiveHour":{"usedPercentage":12.5,"resetsAt":2000003600},"sevenDay":null},"workspace":"must-not-be-modeled","unknown":{"prompt":"must-not-be-modeled"}}"#.utf8)
        try data.write(to: fileURL)
        let reader = ClaudeSnapshotReader(fileURL: fileURL)

        let snapshot = try await reader.readSnapshot()

        XCTAssertEqual(snapshot.schemaVersion, 1)
        XCTAssertEqual(snapshot.capturedAt, Date(timeIntervalSince1970: 2_000_000_000))
        XCTAssertEqual(snapshot.claudeCodeVersion, "2.1.80")
        XCTAssertEqual(snapshot.rateLimits.fiveHour?.usedPercentage, 12.5)
        XCTAssertNil(snapshot.rateLimits.sevenDay)
    }

    func testRejectsUnsupportedSchemaVersion() async {
        let fileURL = temporaryFileURL()
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let data = Data(#"{"schemaVersion":2,"capturedAt":"2033-05-18T03:33:20Z","rateLimits":{"fiveHour":null,"sevenDay":null}}"#.utf8)
        try? data.write(to: fileURL)
        let reader = ClaudeSnapshotReader(fileURL: fileURL)

        do {
            _ = try await reader.readSnapshot()
            XCTFail("Expected an unsupported schema error")
        } catch {
            XCTAssertEqual(error as? ClaudeSnapshotReaderError, .unsupportedSchema(version: 2))
        }
    }

    func testRejectsFutureSchemaBeforeDecodingItsChangedPayload() async {
        let fileURL = temporaryFileURL()
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let data = Data(#"{"schemaVersion":2,"replacementPayload":{}}"#.utf8)
        try? data.write(to: fileURL)
        let reader = ClaudeSnapshotReader(fileURL: fileURL)

        do {
            _ = try await reader.readSnapshot()
            XCTFail("Expected an unsupported schema error")
        } catch {
            XCTAssertEqual(error as? ClaudeSnapshotReaderError, .unsupportedSchema(version: 2))
        }
    }

    func testReportsMissingSnapshotWithoutInspectingClaudeFiles() async {
        let reader = ClaudeSnapshotReader(fileURL: temporaryFileURL())

        do {
            _ = try await reader.readSnapshot()
            XCTFail("Expected a missing snapshot error")
        } catch {
            XCTAssertEqual(error as? ClaudeSnapshotReaderError, .snapshotNotFound)
        }
    }

    func testRejectsSymbolicLinkSnapshot() async throws {
        let targetURL = temporaryFileURL()
        let linkURL = temporaryFileURL()
        defer {
            try? FileManager.default.removeItem(at: linkURL)
            try? FileManager.default.removeItem(at: targetURL)
        }

        let data = Data(#"{"schemaVersion":1,"capturedAt":"2033-05-18T03:33:20Z","rateLimits":{"fiveHour":{"usedPercentage":12.5,"resetsAt":2000003600},"sevenDay":null}}"#.utf8)
        try data.write(to: targetURL)
        try FileManager.default.createSymbolicLink(
            at: linkURL,
            withDestinationURL: targetURL
        )
        let reader = ClaudeSnapshotReader(fileURL: linkURL)

        do {
            _ = try await reader.readSnapshot()
            XCTFail("Expected a symbolic link snapshot to be rejected")
        } catch {
            XCTAssertEqual(error as? ClaudeSnapshotReaderError, .snapshotUnreadable)
        }
    }

    func testRejectsNamedPipeSnapshotWithoutWaitingForAWriter() async throws {
        let fileURL = temporaryFileURL()
        defer { try? FileManager.default.removeItem(at: fileURL) }

        XCTAssertEqual(mkfifo(fileURL.path, S_IRUSR | S_IWUSR), 0)
        let reader = ClaudeSnapshotReader(fileURL: fileURL)

        do {
            _ = try await reader.readSnapshot()
            XCTFail("Expected a named pipe snapshot to be rejected")
        } catch {
            XCTAssertEqual(error as? ClaudeSnapshotReaderError, .snapshotUnreadable)
        }
    }

    func testRejectsMalformedOrPartialSnapshot() async {
        let fileURL = temporaryFileURL()
        defer { try? FileManager.default.removeItem(at: fileURL) }

        try? Data(#"{"schemaVersion":1,"capturedAt":"2033-05-18T03:33:20Z""#.utf8)
            .write(to: fileURL)
        let reader = ClaudeSnapshotReader(fileURL: fileURL)

        do {
            _ = try await reader.readSnapshot()
            XCTFail("Expected an invalid snapshot error")
        } catch {
            XCTAssertEqual(error as? ClaudeSnapshotReaderError, .invalidSnapshot)
        }
    }

    func testRejectsOversizedSnapshotBeforeDecoding() async {
        let fileURL = temporaryFileURL()
        defer { try? FileManager.default.removeItem(at: fileURL) }

        try? Data(repeating: 0x20, count: 65).write(to: fileURL)
        let reader = ClaudeSnapshotReader(fileURL: fileURL, maximumBytes: 64)

        do {
            _ = try await reader.readSnapshot()
            XCTFail("Expected an oversized snapshot error")
        } catch {
            XCTAssertEqual(error as? ClaudeSnapshotReaderError, .snapshotTooLarge)
        }
    }

    private func temporaryFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appendingPathExtension("json")
    }
}
