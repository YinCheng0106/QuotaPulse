import AppKit
import Darwin
import Foundation
import XCTest
@testable import QuotaPulse

final class CodexAppServerClientTests: XCTestCase {
    func testRepeatedReadsReuseOneHealthyProcess() async throws {
        let script = #"""
        IFS= read -r initialize
        IFS= read -r initialized
        count=0
        while IFS= read -r rate_limits; do
            count=$((count + 1))
            id=$((count + 1))
            printf '{"id":%s,"result":{"rateLimits":{"primary":{"usedPercent":%s}}}}\n' "$id" "$count"
        done
        """#
        let client = CodexAppServerClient(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", script],
            timeout: .seconds(1)
        )

        let first = try await client.readRateLimits()
        let second = try await client.readRateLimits()
        await client.shutdown()

        XCTAssertEqual(first.rateLimits?.primary?.usedPercent, 1)
        XCTAssertEqual(second.rateLimits?.primary?.usedPercent, 2)
    }

    func testConcurrentReadsShareOneRequestAndOneProcess() async throws {
        let script = #"""
        IFS= read -r initialize
        IFS= read -r initialized
        count=0
        while IFS= read -r rate_limits; do
            count=$((count + 1))
            id=$((count + 1))
            /bin/sleep 0.1
            printf '{"id":%s,"result":{"rateLimits":{"primary":{"usedPercent":%s}}}}\n' "$id" "$count"
        done
        """#
        let client = CodexAppServerClient(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", script],
            timeout: .seconds(1)
        )

        async let first = client.readRateLimits()
        await Task.yield()
        async let second = client.readRateLimits()
        let (firstResult, secondResult) = try await (first, second)
        let thirdResult = try await client.readRateLimits()
        await client.shutdown()

        XCTAssertEqual(firstResult.rateLimits?.primary?.usedPercent, 1)
        XCTAssertEqual(secondResult.rateLimits?.primary?.usedPercent, 1)
        XCTAssertEqual(thirdResult.rateLimits?.primary?.usedPercent, 2)
    }

    func testReconnectReapsFailedProcessBeforeStartingReplacement() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let launchCountURL = directory.appending(path: "launch-count")
        let firstPIDURL = directory.appending(path: "first-pid")
        try Data("0".utf8).write(to: launchCountURL)

        let script = #"""
        launch_count=$(/bin/cat "$0")
        launch_count=$((launch_count + 1))
        printf '%s' "$launch_count" > "$0"
        IFS= read -r initialize
        IFS= read -r initialized
        IFS= read -r rate_limits
        if [ "$launch_count" -eq 1 ]; then
            printf '%s' "$$" > "$1"
            exit 0
        fi
        printf '%s\n' '{"id":3,"result":{"rateLimits":{"primary":{"usedPercent":42}}}}'
        while IFS= read -r rate_limits; do :; done
        """#
        let client = CodexAppServerClient(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", script, launchCountURL.path, firstPIDURL.path],
            timeout: .seconds(1)
        )

        do {
            _ = try await client.readRateLimits()
            XCTFail("Expected the first app-server process to exit")
        } catch {
            XCTAssertEqual(error as? CodexAppServerError, .noResponse)
        }

        let firstPID = try processID(at: firstPIDURL)
        XCTAssertTrue(isReaped(firstPID), "The failed child must be reaped before reconnect")

        let response = try await client.readRateLimits()
        await client.shutdown()

        XCTAssertEqual(response.rateLimits?.primary?.usedPercent, 42)
        XCTAssertEqual(try String(contentsOf: launchCountURL, encoding: .utf8), "2")
    }

    func testShutdownClosesPipesAndReapsHealthyProcess() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let pidURL = directory.appending(path: "pid")

        let script = #"""
        printf '%s' "$$" > "$0"
        IFS= read -r initialize
        IFS= read -r initialized
        IFS= read -r rate_limits
        printf '%s\n' '{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":25}}}}'
        while IFS= read -r rate_limits; do :; done
        """#
        let client = CodexAppServerClient(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", script, pidURL.path],
            timeout: .seconds(1)
        )

        _ = try await client.readRateLimits()
        let pid = try processID(at: pidURL)
        XCTAssertFalse(isReaped(pid))

        await client.shutdown()

        XCTAssertTrue(isReaped(pid), "Shutdown must close handles, terminate, and reap the child")
    }

    func testApplicationTerminationNotificationReapsHealthyProcess() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let pidURL = directory.appending(path: "pid")
        let notificationCenter = NotificationCenter()

        let script = #"""
        printf '%s' "$$" > "$0"
        IFS= read -r initialize
        IFS= read -r initialized
        IFS= read -r rate_limits
        printf '%s\n' '{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":25}}}}'
        while IFS= read -r rate_limits; do :; done
        """#
        let client = CodexAppServerClient(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", script, pidURL.path],
            timeout: .seconds(1),
            notificationCenter: notificationCenter
        )

        _ = try await client.readRateLimits()
        let pid = try processID(at: pidURL)

        notificationCenter.post(name: NSApplication.willTerminateNotification, object: nil)

        XCTAssertTrue(isReaped(pid), "Application termination must synchronously reap the child")
        await client.shutdown()
    }

    func testReadsDocumentedRateLimitResponseFromProcess() async throws {
        let script = #"""
        IFS= read -r initialize
        IFS= read -r initialized
        IFS= read -r rate_limits
        printf '%s\n' '{"id":1,"result":{}}'
        printf '%s\n' '{"id":2,"result":{"rateLimits":{"limitId":"codex","limitName":null,"primary":{"usedPercent":25,"windowDurationMins":300,"resetsAt":2000003600},"secondary":null},"rateLimitsByLimitId":null}}'
        """#
        let client = CodexAppServerClient(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", script],
            timeout: .seconds(1),
            maximumResponseBytes: 8_192
        )

        let response = try await client.readRateLimits()

        XCTAssertEqual(response.rateLimits?.limitId, "codex")
        XCTAssertEqual(response.rateLimits?.primary?.usedPercent, 25)
        XCTAssertEqual(response.rateLimits?.primary?.windowDurationMins, 300)
        XCTAssertEqual(response.rateLimits?.primary?.resetsAt, 2_000_003_600)
    }

    func testHealthyRequestProducesConnectedCompatibleRuntimeDiagnostic() async throws {
        let script = #"""
        IFS= read -r initialize
        IFS= read -r initialized
        IFS= read -r rate_limits
        printf '%s\n' '{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":25}}}}'
        while IFS= read -r rate_limits; do :; done
        """#
        let client = CodexAppServerClient(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", script],
            timeout: .seconds(1)
        )

        _ = try await client.readRateLimits()
        let diagnostics = await client.runtimeDiagnostic()
        await client.shutdown()

        XCTAssertEqual(diagnostics.runtimeSource, .standaloneCodex)
        XCTAssertEqual(diagnostics.runtimeDetected, true)
        XCTAssertEqual(diagnostics.compatibilityStatus, .compatible)
        XCTAssertEqual(diagnostics.appServerState, .connected)
        XCTAssertNil(diagnostics.lastFailureCategory)
    }

    func testTimeoutProducesSanitizedConnectionFailureDiagnostic() async {
        let script = #"""
        IFS= read -r initialize
        IFS= read -r initialized
        IFS= read -r rate_limits
        exec /bin/sleep 5
        """#
        let client = CodexAppServerClient(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", script],
            timeout: .milliseconds(100)
        )

        _ = try? await client.readRateLimits()
        let diagnostics = await client.runtimeDiagnostic()

        XCTAssertEqual(diagnostics.runtimeDetected, true)
        XCTAssertEqual(diagnostics.compatibilityStatus, .unverified)
        XCTAssertEqual(diagnostics.appServerState, .disconnected)
        XCTAssertEqual(diagnostics.lastFailureCategory, .appServerConnectionFailed)
    }

    func testDoesNotExposeCallerWorkingDirectoryToAppServer() async throws {
        let script = #"""
        test "$PWD" = / || exit 1
        IFS= read -r initialize
        IFS= read -r initialized
        IFS= read -r rate_limits
        printf '%s\n' '{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":25}}}}'
        """#
        let client = CodexAppServerClient(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", script],
            timeout: .seconds(1),
            maximumResponseBytes: 8_192
        )

        let response = try await client.readRateLimits()

        XCTAssertEqual(response.rateLimits?.primary?.usedPercent, 25)
    }

    func testDecodesMissingOptionalFieldsAsUnavailable() async throws {
        let script = #"""
        IFS= read -r initialize
        IFS= read -r initialized
        IFS= read -r rate_limits
        printf '%s\n' '{"id":1,"result":{}}'
        printf '%s\n' '{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":20}}}}'
        """#
        let client = CodexAppServerClient(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", script],
            timeout: .seconds(1),
            maximumResponseBytes: 8_192
        )

        let response = try await client.readRateLimits()

        XCTAssertEqual(response.rateLimits?.primary?.usedPercent, 20)
        XCTAssertNil(response.rateLimits?.primary?.windowDurationMins)
        XCTAssertNil(response.rateLimits?.primary?.resetsAt)
        XCTAssertNil(response.rateLimits?.secondary)
    }

    func testTerminatesProcessAtTimeout() async {
        let script = #"""
        IFS= read -r initialize
        IFS= read -r initialized
        IFS= read -r rate_limits
        exec /bin/sleep 5
        """#
        let client = CodexAppServerClient(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", script],
            timeout: .milliseconds(100)
        )

        do {
            _ = try await client.readRateLimits()
            XCTFail("Expected the app-server request to time out")
        } catch {
            XCTAssertEqual(error as? CodexAppServerError, .timeout)
        }
    }

    func testCancellationStopsWaitingForProcessOutput() async {
        let script = #"""
        IFS= read -r initialize
        IFS= read -r initialized
        IFS= read -r rate_limits
        exec /bin/sleep 5
        """#
        let client = CodexAppServerClient(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", script],
            timeout: .seconds(5)
        )
        let request = Task {
            try await client.readRateLimits()
        }

        try? await Task.sleep(for: .milliseconds(100))
        request.cancel()

        do {
            _ = try await request.value
            XCTFail("Expected the app-server request to be cancelled")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Expected CancellationError, received \(error)")
        }
    }

    func testRejectsOversizedOutput() async {
        let script = #"""
        IFS= read -r initialize
        IFS= read -r initialized
        IFS= read -r rate_limits
        printf '%0200d\n' 0
        """#
        let client = CodexAppServerClient(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", script],
            timeout: .seconds(1),
            maximumResponseBytes: 100
        )

        do {
            _ = try await client.readRateLimits()
            XCTFail("Expected oversized output to be rejected")
        } catch {
            XCTAssertEqual(error as? CodexAppServerError, .responseTooLarge)
        }
    }

    func testRejectsMalformedResponse() async {
        let script = #"""
        IFS= read -r initialize
        IFS= read -r initialized
        IFS= read -r rate_limits
        printf '%s\n' 'not-json'
        """#
        let client = CodexAppServerClient(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", script],
            timeout: .seconds(1),
            maximumResponseBytes: 8_192
        )

        do {
            _ = try await client.readRateLimits()
            XCTFail("Expected malformed output to be rejected")
        } catch {
            XCTAssertEqual(error as? CodexAppServerError, .invalidResponse)
        }
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "CodexAppServerClientTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func processID(at url: URL) throws -> pid_t {
        let value = try String(contentsOf: url, encoding: .utf8)
        return try XCTUnwrap(pid_t(value))
    }

    private func isReaped(_ pid: pid_t) -> Bool {
        errno = 0
        return kill(pid, 0) == -1 && errno == ESRCH
    }
}
