import AppKit
import Darwin
import Foundation

protocol CodexRateLimitsReading: Sendable {
    func readRateLimits() async throws -> CodexRateLimitsResult
}

protocol CodexRuntimeDiagnosticReading: Sendable {
    func runtimeDiagnostic() async -> ProviderRuntimeDiagnostic
}

enum CodexAppServerError: Error, Equatable, Sendable {
    case executableNotFound
    case launchFailed
    case timeout
    case responseTooLarge
    case invalidResponse
    case serverError(code: Int?)
    case noResponse
}

extension CodexAppServerError: ProviderStatusProvidingError {
    var providerStatus: ProviderStatus {
        switch self {
        case .executableNotFound:
            .notInstalled
        case .launchFailed:
            .failed(.runtimeLaunchFailed)
        case .timeout, .responseTooLarge, .invalidResponse, .serverError, .noResponse:
            .failed(.refreshFailed)
        }
    }
}

actor CodexAppServerClient: CodexRateLimitsReading, CodexRuntimeDiagnosticReading {
    private static let initializeRequestID = 1
    private static let firstRateLimitsRequestID = 2

    private let executableURL: URL?
    private let locator: CodexExecutableLocator?
    private let arguments: [String]
    private let timeout: Duration
    private let maximumResponseBytes: Int
    private let lifecycle: CodexConnectionLifecycle

    private struct InFlightRequest {
        let generation: UInt64
        let task: Task<CodexRateLimitsResult, Error>
    }

    private var nextRequestID = firstRateLimitsRequestID
    private var nextRequestGeneration: UInt64 = 1
    private var inFlightRequest: InFlightRequest?
    private var hasStartedAppServerProcess = false
    private var lastRequestSucceeded = false
    private var lastFailureCategory: DiagnosticFailureCategory?

    init(
        executableURL: URL,
        arguments: [String] = ["app-server"],
        timeout: Duration = .seconds(5),
        maximumResponseBytes: Int = 1_048_576,
        notificationCenter: NotificationCenter = .default
    ) {
        self.executableURL = executableURL
        self.locator = nil
        self.arguments = arguments
        self.timeout = timeout
        self.maximumResponseBytes = max(maximumResponseBytes, 1)
        self.lifecycle = CodexConnectionLifecycle(notificationCenter: notificationCenter)
    }

    init(
        locator: CodexExecutableLocator,
        timeout: Duration = .seconds(5),
        maximumResponseBytes: Int = 1_048_576,
        notificationCenter: NotificationCenter = .default
    ) {
        self.executableURL = nil
        self.locator = locator
        self.arguments = ["app-server"]
        self.timeout = timeout
        self.maximumResponseBytes = max(maximumResponseBytes, 1)
        self.lifecycle = CodexConnectionLifecycle(notificationCenter: notificationCenter)
    }

    func readRateLimits() async throws -> CodexRateLimitsResult {
        do {
            let result = try await readRateLimitsCoalesced()
            lastRequestSucceeded = true
            lastFailureCategory = nil
            return result
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            lastRequestSucceeded = false
            lastFailureCategory = Self.failureCategory(for: error)
            throw error
        }
    }

    func runtimeDiagnostic() async -> ProviderRuntimeDiagnostic {
        let discovery: CodexRuntimeDiscovery
        if let locator {
            discovery = locator.diagnosticSnapshot()
        } else {
            let isDetected = executableURL.map {
                FileManager.default.isExecutableFile(atPath: $0.path)
            } ?? false
            discovery = CodexRuntimeDiscovery(
                chatGPTApplication: DiagnosticHostApplicationState(
                    application: .chatGPT,
                    isDetected: false,
                    version: nil
                ),
                runtimeSource: isDetected ? .standaloneCodex : .notDetected,
                runtimeDetected: isDetected,
                failureCategory: isDetected ? nil : .runtimeNotDetected
            )
        }

        let isConnected = lifecycle.connection?.isHealthy == true
        let appServerState: DiagnosticAppServerState
        if isConnected {
            appServerState = .connected
        } else if lastFailureCategory == .appServerLaunchFailed {
            appServerState = .launchFailed
        } else if hasStartedAppServerProcess {
            appServerState = .disconnected
        } else {
            appServerState = .notStarted
        }

        let compatibilityStatus: DiagnosticCompatibilityStatus
        if lastRequestSucceeded {
            compatibilityStatus = .compatible
        } else if discovery.runtimeDetected {
            compatibilityStatus = .unverified
        } else {
            compatibilityStatus = .unavailable
        }

        return ProviderRuntimeDiagnostic(
            hostApplication: discovery.chatGPTApplication,
            runtimeSource: discovery.runtimeSource,
            runtimeDetected: discovery.runtimeDetected,
            compatibilityStatus: compatibilityStatus,
            appServerState: appServerState,
            lastFailureCategory: lastFailureCategory ?? discovery.failureCategory
        )
    }

    private func readRateLimitsCoalesced() async throws -> CodexRateLimitsResult {
        if let inFlightRequest {
            return try await awaitRequest(inFlightRequest.task)
        }

        let generation = nextRequestGeneration
        nextRequestGeneration &+= 1
        let task = Task {
            try await performReadRateLimits()
        }
        inFlightRequest = InFlightRequest(generation: generation, task: task)

        do {
            let result = try await awaitRequest(task)
            clearInFlightRequest(generation: generation)
            return result
        } catch {
            clearInFlightRequest(generation: generation)
            throw error
        }
    }

    func shutdown() async {
        inFlightRequest?.task.cancel()
        inFlightRequest = nil

        if let connection = lifecycle.beginShutdown() {
            await connection.stop()
        }
    }

    private func clearInFlightRequest(generation: UInt64) {
        guard inFlightRequest?.generation == generation else { return }
        inFlightRequest = nil
    }

    private func awaitRequest(
        _ task: Task<CodexRateLimitsResult, Error>
    ) async throws -> CodexRateLimitsResult {
        try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
            lifecycle.stopCurrentConnection()
        }
    }

    private func performReadRateLimits() async throws -> CodexRateLimitsResult {
        try Task.checkCancellation()
        let connection = try await healthyConnection()
        let requestID = nextRequestID
        nextRequestID = nextRequestID == Int.max ? Self.firstRateLimitsRequestID : nextRequestID + 1

        do {
            try connection.writeRateLimitsRequest(id: requestID)
            return try await response(id: requestID, from: connection)
        } catch {
            await disconnect(connection)
            try Task.checkCancellation()
            throw error
        }
    }

    private func healthyConnection() async throws -> ManagedCodexConnection {
        if let connection = lifecycle.connection, connection.isHealthy {
            #if DEBUG
            RuntimeDiagnostics.shared.codexConnectionBecameHealthy(
                processID: connection.processIdentifier
            )
            #endif
            return connection
        }

        if let staleConnection = lifecycle.takeConnection() {
            await staleConnection.stop()
        }

        guard let executableURL = locator?.locate() ?? executableURL,
              FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            throw CodexAppServerError.executableNotFound
        }

        let process = Process()
        let standardInput = Pipe()
        let standardOutput = Pipe()

        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: "/", isDirectory: true)
        process.standardInput = standardInput
        process.standardOutput = standardOutput
        // Never buffer provider stderr in QuotaPulse.
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            hasStartedAppServerProcess = true
        } catch {
            try? standardInput.fileHandleForWriting.close()
            try? standardOutput.fileHandleForReading.close()
            process.standardInput = nil
            process.standardOutput = nil
            throw CodexAppServerError.launchFailed
        }

        #if DEBUG
        RuntimeDiagnostics.shared.codexProcessStarted(process.processIdentifier)
        #endif

        let connection = ManagedCodexConnection(
            process: process,
            input: standardInput.fileHandleForWriting,
            output: standardOutput.fileHandleForReading,
            maximumResponseBytes: maximumResponseBytes
        )

        do {
            try connection.writeInitialization(id: Self.initializeRequestID)
            guard lifecycle.install(connection) else {
                await connection.stop()
                throw CancellationError()
            }
            #if DEBUG
            RuntimeDiagnostics.shared.codexConnectionBecameHealthy(
                processID: connection.processIdentifier
            )
            #endif
            return connection
        } catch {
            await connection.stop()
            throw error
        }
    }

    private func response(
        id: Int,
        from connection: ManagedCodexConnection
    ) async throws -> CodexRateLimitsResult {
        let timeout = timeout
        return try await withThrowingTaskGroup(of: CodexRateLimitsResult.self) { group in
            group.addTask {
                try await connection.response(for: id)
            }

            group.addTask {
                try await Task.sleep(for: timeout)
                connection.markTimedOutAndRequestStop()
                throw CodexAppServerError.timeout
            }

            guard let result = try await group.next() else {
                throw CodexAppServerError.noResponse
            }

            group.cancelAll()
            return result
        }
    }

    private func disconnect(_ connection: ManagedCodexConnection) async {
        lifecycle.remove(connection)
        await connection.stop()
    }

    private static func failureCategory(for error: Error) -> DiagnosticFailureCategory? {
        guard let error = error as? CodexAppServerError else { return .refreshFailed }
        switch error {
        case .executableNotFound:
            return .runtimeNotDetected
        case .launchFailed:
            return .appServerLaunchFailed
        case .timeout, .noResponse:
            return .appServerConnectionFailed
        case .responseTooLarge, .invalidResponse, .serverError:
            return .rpcUnavailable
        }
    }
}

private struct CodexAppServerEnvelope: Decodable, Sendable {
    let id: Int?
    let result: CodexRateLimitsResult?
    let error: CodexAppServerResponseError?
}

private struct CodexAppServerResponseError: Decodable, Sendable {
    let code: Int?
}

private final class CodexConnectionLifecycle: @unchecked Sendable {
    private let lock = NSLock()
    private let notificationCenter: NotificationCenter
    private var currentConnection: ManagedCodexConnection?
    private var terminationObserver: NSObjectProtocol?
    private var isShutdown = false

    init(notificationCenter: NotificationCenter = .default) {
        self.notificationCenter = notificationCenter
        terminationObserver = notificationCenter.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.shutdownSynchronously()
        }
    }

    deinit {
        if let terminationObserver {
            notificationCenter.removeObserver(terminationObserver)
        }
        shutdownSynchronously()
    }

    var connection: ManagedCodexConnection? {
        lock.withLock { currentConnection }
    }

    func install(_ connection: ManagedCodexConnection) -> Bool {
        let installation: (accepted: Bool, oldConnection: ManagedCodexConnection?) = lock.withLock {
            guard !isShutdown else { return (accepted: false, oldConnection: nil) }
            let oldConnection = currentConnection
            currentConnection = connection
            return (accepted: true, oldConnection: oldConnection)
        }
        installation.oldConnection?.requestStop()
        return installation.accepted
    }

    func remove(_ connection: ManagedCodexConnection) {
        lock.withLock {
            guard currentConnection === connection else { return }
            currentConnection = nil
        }
    }

    func takeConnection() -> ManagedCodexConnection? {
        lock.withLock {
            defer { currentConnection = nil }
            return currentConnection
        }
    }

    func stopCurrentConnection() {
        takeConnection()?.requestStop()
    }

    func beginShutdown() -> ManagedCodexConnection? {
        lock.withLock {
            isShutdown = true
            defer { currentConnection = nil }
            return currentConnection
        }
    }

    private func shutdownSynchronously() {
        beginShutdown()?.requestStop()
    }
}

private final class ExpectedCodexResponse: @unchecked Sendable {
    private let lock = NSLock()
    private var requestID: Int?

    func set(_ requestID: Int) {
        lock.withLock {
            self.requestID = requestID
        }
    }

    func matches(_ requestID: Int?) -> Bool {
        lock.withLock {
            requestID == self.requestID
        }
    }
}

private final class ManagedCodexConnection: @unchecked Sendable {
    private let condition = NSCondition()
    private let process: Process
    private let input: FileHandle
    private let output: FileHandle
    private let responses: AsyncThrowingStream<CodexAppServerEnvelope, Error>
    private let responseContinuation: AsyncThrowingStream<CodexAppServerEnvelope, Error>.Continuation
    private let expectedResponse = ExpectedCodexResponse()
    private let stdoutTask: Task<Void, Never>

    private var didRequestStop = false
    private var didFinishStop = false
    private var didTimeOut = false

    init(
        process: Process,
        input: FileHandle,
        output: FileHandle,
        maximumResponseBytes: Int
    ) {
        self.process = process
        self.input = input
        self.output = output

        let channel = AsyncThrowingStream<CodexAppServerEnvelope, Error>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        responses = channel.stream
        responseContinuation = channel.continuation

        let expectedResponse = expectedResponse
        stdoutTask = Task.detached(priority: .utility) {
            await CodexStdoutReader.run(
                output: output,
                maximumResponseBytes: maximumResponseBytes,
                expectedResponse: expectedResponse,
                continuation: channel.continuation
            )
        }

        #if DEBUG
        RuntimeDiagnostics.shared.codexStdoutReaderStarted(
            processID: process.processIdentifier
        )
        #endif
    }

    deinit {
        requestStop()
    }

    var isHealthy: Bool {
        condition.lock()
        defer { condition.unlock() }
        return !didRequestStop && process.isRunning
    }

    var processIdentifier: pid_t {
        process.processIdentifier
    }

    func writeInitialization(id: Int) throws {
        try write([
            [
                "method": "initialize",
                "id": id,
                "params": [
                    "clientInfo": [
                        "name": "quota_pulse",
                        "title": "QuotaPulse",
                        "version": "0.1.0"
                    ]
                ]
            ],
            [
                "method": "initialized",
                "params": [:]
            ]
        ])
    }

    func writeRateLimitsRequest(id: Int) throws {
        expectedResponse.set(id)
        try write([[
            "method": "account/rateLimits/read",
            "id": id
        ]])
    }

    func response(for requestID: Int) async throws -> CodexRateLimitsResult {
        do {
            for try await envelope in responses {
                guard envelope.id == requestID else { continue }

                if let error = envelope.error {
                    throw CodexAppServerError.serverError(code: error.code)
                }
                guard let result = envelope.result else {
                    throw CodexAppServerError.invalidResponse
                }
                return result
            }
        } catch {
            if timedOut {
                throw CodexAppServerError.timeout
            }
            try Task.checkCancellation()
            throw error
        }

        throw timedOut ? CodexAppServerError.timeout : CodexAppServerError.noResponse
    }

    func markTimedOutAndRequestStop() {
        condition.lock()
        didTimeOut = true
        condition.unlock()
        requestStop()
    }

    func requestStop() {
        condition.lock()
        if didRequestStop {
            while !didFinishStop {
                condition.wait()
            }
            condition.unlock()
            return
        }
        didRequestStop = true
        condition.unlock()

        #if DEBUG
        RuntimeDiagnostics.shared.codexConnectionStopping(
            processID: process.processIdentifier
        )
        #endif

        responseContinuation.finish(throwing: CancellationError())
        stdoutTask.cancel()
        try? input.close()
        try? output.close()

        if process.isRunning {
            process.terminate()
        }

        for _ in 0..<50 where process.isRunning {
            usleep(10_000)
        }
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }
        // Foundation has already observed and reaped the child once isRunning becomes false.
        if process.isRunning {
            process.waitUntilExit()
        }

        condition.lock()
        didFinishStop = true
        condition.broadcast()
        condition.unlock()

        #if DEBUG
        RuntimeDiagnostics.shared.codexProcessStopped(process.processIdentifier)
        #endif
    }

    func stop() async {
        requestStop()
        await stdoutTask.value
        #if DEBUG
        RuntimeDiagnostics.shared.codexStdoutReaderStopped(
            processID: process.processIdentifier
        )
        #endif
    }

    private var timedOut: Bool {
        condition.lock()
        defer { condition.unlock() }
        return didTimeOut
    }

    private func write(_ requests: [[String: Any]]) throws {
        condition.lock()
        defer { condition.unlock() }

        guard !didRequestStop, process.isRunning else {
            throw CodexAppServerError.noResponse
        }

        do {
            for request in requests {
                var data = try JSONSerialization.data(withJSONObject: request)
                data.append(0x0A)
                try input.write(contentsOf: data)
            }
        } catch let error as CodexAppServerError {
            throw error
        } catch {
            throw CodexAppServerError.noResponse
        }
    }
}

private enum CodexStdoutReader {
    static func run(
        output: FileHandle,
        maximumResponseBytes: Int,
        expectedResponse: ExpectedCodexResponse,
        continuation: AsyncThrowingStream<CodexAppServerEnvelope, Error>.Continuation
    ) async {
        var line = Data()

        do {
            for try await byte in output.bytes {
                try Task.checkCancellation()

                if byte == 0x0A {
                    try yieldResponse(
                        from: line,
                        expectedResponse: expectedResponse,
                        continuation: continuation
                    )
                    line.removeAll(keepingCapacity: false)
                    continue
                }

                guard line.count < maximumResponseBytes else {
                    throw CodexAppServerError.responseTooLarge
                }
                line.append(byte)
            }

            try yieldResponse(
                from: line,
                expectedResponse: expectedResponse,
                continuation: continuation
            )
            continuation.finish()
        } catch is CancellationError {
            continuation.finish(throwing: CancellationError())
        } catch let error as CodexAppServerError {
            continuation.finish(throwing: error)
        } catch {
            continuation.finish(throwing: CodexAppServerError.noResponse)
        }
    }

    private static func yieldResponse(
        from data: Data,
        expectedResponse: ExpectedCodexResponse,
        continuation: AsyncThrowingStream<CodexAppServerEnvelope, Error>.Continuation
    ) throws {
        guard !data.isEmpty else { return }

        let envelope: CodexAppServerEnvelope
        do {
            envelope = try JSONDecoder().decode(CodexAppServerEnvelope.self, from: data)
        } catch {
            throw CodexAppServerError.invalidResponse
        }

        guard expectedResponse.matches(envelope.id) else { return }
        continuation.yield(envelope)
    }
}
