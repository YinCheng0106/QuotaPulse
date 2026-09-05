import Foundation

enum CodexProviderError: Error, Equatable, Sendable {
    case noRateLimits
}

extension CodexProviderError: ProviderStatusProvidingError {
    var providerStatus: ProviderStatus {
        .failed(.usageUnavailable)
    }
}

struct CodexProvider: UsageProvider, Sendable {
    let id = ProviderID.codex

    private let reader: any CodexRateLimitsReading
    private let runtimeDiagnosticReader: (any CodexRuntimeDiagnosticReading)?
    private let now: @Sendable () -> Date
    private let locale: Locale

    init(
        reader: any CodexRateLimitsReading,
        runtimeDiagnosticReader: (any CodexRuntimeDiagnosticReading)? = nil,
        now: @escaping @Sendable () -> Date = Date.init,
        locale: Locale = .autoupdatingCurrent
    ) {
        self.reader = reader
        self.runtimeDiagnosticReader = runtimeDiagnosticReader
        self.now = now
        self.locale = locale
    }

    init(
        locator: CodexExecutableLocator = CodexExecutableLocator(),
        now: @escaping @Sendable () -> Date = Date.init,
        locale: Locale = .autoupdatingCurrent
    ) {
        let client = CodexAppServerClient(locator: locator)
        self.init(
            reader: client,
            runtimeDiagnosticReader: client,
            now: now,
            locale: locale
        )
    }

    func runtimeDiagnostic() async -> ProviderRuntimeDiagnostic {
        guard let runtimeDiagnosticReader else { return .unknown }
        return await runtimeDiagnosticReader.runtimeDiagnostic()
    }

    func fetchUsage() async throws -> ProviderUsageSnapshot {
        let response = try await reader.readRateLimits()
        let buckets = normalizedBuckets(from: response)
        let windows = buckets.flatMap(makeUsageWindows)

        guard !windows.isEmpty else {
            throw CodexProviderError.noRateLimits
        }

        return ProviderUsageSnapshot(
            providerID: .codex,
            windows: windows,
            capturedAt: now(),
            source: UsageSource(
                kind: .codexAppServer,
                label: "Codex app-server",
                documentationURL: URL(string: "https://learn.chatgpt.com/docs/app-server")
            )
        )
    }

    private func normalizedBuckets(
        from response: CodexRateLimitsResult
    ) -> [(id: String, bucket: CodexRateLimitBucket)] {
        if let buckets = response.rateLimitsByLimitId, !buckets.isEmpty {
            return buckets
                .map { key, value in (id: key, bucket: value) }
                .sorted { $0.id < $1.id }
        }

        if let bucket = response.rateLimits {
            return [(id: bucket.limitId ?? "codex", bucket: bucket)]
        }

        return []
    }

    private func makeUsageWindows(
        bucket: (id: String, bucket: CodexRateLimitBucket)
    ) -> [UsageWindow] {
        var windows: [UsageWindow] = []

        if let primary = makeUsageWindow(
            bucketID: bucket.id,
            bucketName: bucket.bucket.limitName,
            role: "primary",
            window: bucket.bucket.primary
        ) {
            windows.append(primary)
        }

        if let secondary = makeUsageWindow(
            bucketID: bucket.id,
            bucketName: bucket.bucket.limitName,
            role: "secondary",
            window: bucket.bucket.secondary
        ) {
            windows.append(secondary)
        }

        return windows
    }

    private func makeUsageWindow(
        bucketID: String,
        bucketName: String?,
        role: String,
        window: CodexRateLimitWindow?
    ) -> UsageWindow? {
        guard let window else {
            return nil
        }

        let usedPercent = window.usedPercent.flatMap { $0.isFinite ? $0 : nil }

        let duration = window.windowDurationMins.flatMap { minutes -> Duration? in
            guard minutes > 0, minutes <= Int.max / 60 else { return nil }
            return .seconds(minutes * 60)
        }

        let resetAt = window.resetsAt.flatMap { timestamp -> Date? in
            guard timestamp.isFinite, timestamp > 0 else { return nil }
            return Date(timeIntervalSince1970: timestamp)
        }

        guard usedPercent != nil || resetAt != nil else { return nil }

        let displayName = bucketName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = displayName.flatMap { $0.isEmpty ? nil : $0 }
        let roleLabel = role == "primary"
            ? AppLocalization.string("Primary window", locale: locale)
            : AppLocalization.string("Secondary window", locale: locale)
        let label = prefix.map { "\($0) · \(roleLabel)" } ?? roleLabel

        return UsageWindow(
            id: "codex.\(bucketID).\(role)",
            label: label,
            usedPercentage: usedPercent,
            resetAt: resetAt,
            duration: duration
        )
    }
}
