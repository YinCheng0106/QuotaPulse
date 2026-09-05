import Foundation
import Darwin

protocol ClaudeUsageSnapshotReading: Sendable {
    func readSnapshot() async throws -> ClaudeUsageSnapshotDocument
}

enum ClaudeSnapshotReaderError: Error, Equatable, Sendable {
    case snapshotNotFound
    case snapshotUnreadable
    case snapshotTooLarge
    case invalidSnapshot
    case unsupportedSchema(version: Int)
}

extension ClaudeSnapshotReaderError: ProviderStatusProvidingError {
    var providerStatus: ProviderStatus {
        switch self {
        case .snapshotNotFound:
            .notConfigured
        case .snapshotUnreadable, .snapshotTooLarge, .invalidSnapshot, .unsupportedSchema:
            .failed(.refreshFailed)
        }
    }
}

private struct ClaudeSnapshotEnvelope: Decodable {
    let schemaVersion: Int
}

struct ClaudeSnapshotReader: ClaudeUsageSnapshotReading, Sendable {
    static let supportedSchemaVersion = 1

    private let fileURL: URL
    private let maximumBytes: Int

    init(
        fileURL: URL = Self.defaultSnapshotURL(),
        maximumBytes: Int = 16_384
    ) {
        self.fileURL = fileURL
        self.maximumBytes = max(maximumBytes, 1)
    }

    func readSnapshot() async throws -> ClaudeUsageSnapshotDocument {
        try Task.checkCancellation()

        let handle = try openSnapshot()
        defer { try? handle.close() }

        let data: Data
        do {
            data = try handle.read(upToCount: maximumBytes + 1) ?? Data()
        } catch {
            throw ClaudeSnapshotReaderError.snapshotUnreadable
        }

        try Task.checkCancellation()

        guard data.count <= maximumBytes else {
            throw ClaudeSnapshotReaderError.snapshotTooLarge
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let envelope: ClaudeSnapshotEnvelope
        do {
            envelope = try decoder.decode(ClaudeSnapshotEnvelope.self, from: data)
        } catch {
            throw ClaudeSnapshotReaderError.invalidSnapshot
        }

        guard envelope.schemaVersion == Self.supportedSchemaVersion else {
            throw ClaudeSnapshotReaderError.unsupportedSchema(version: envelope.schemaVersion)
        }

        do {
            return try decoder.decode(ClaudeUsageSnapshotDocument.self, from: data)
        } catch {
            throw ClaudeSnapshotReaderError.invalidSnapshot
        }
    }

    private func openSnapshot() throws -> FileHandle {
        let descriptor = open(
            fileURL.path,
            O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK
        )

        guard descriptor >= 0 else {
            if errno == ENOENT {
                throw ClaudeSnapshotReaderError.snapshotNotFound
            }
            throw ClaudeSnapshotReaderError.snapshotUnreadable
        }

        var metadata = stat()
        guard
            fstat(descriptor, &metadata) == 0,
            metadata.st_mode & S_IFMT == S_IFREG
        else {
            Darwin.close(descriptor)
            throw ClaudeSnapshotReaderError.snapshotUnreadable
        }

        return FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    }

    private static func defaultSnapshotURL() -> URL {
        FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        .appending(path: "QuotaPulse/Providers/Claude/usage-v1.json")
    }
}
