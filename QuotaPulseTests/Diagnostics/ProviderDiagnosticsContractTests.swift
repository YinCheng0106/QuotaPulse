import XCTest
@testable import QuotaPulse

final class ProviderDiagnosticsContractTests: XCTestCase {
    func testOnDemandDiagnosticsDoNotFetchProviderUsage() async {
        let provider = DiagnosticsCountingProvider()
        let service = UsageService(providers: [provider])

        let diagnostics = await service.providerDiagnostics()
        let counts = await provider.counts

        XCTAssertEqual(diagnostics.count, 1)
        XCTAssertEqual(diagnostics.first?.providerID, .codex)
        XCTAssertEqual(diagnostics.first?.runtime.runtimeSource, .standaloneCodex)
        XCTAssertEqual(counts.fetches, 0)
        XCTAssertEqual(counts.diagnostics, 1)
    }

    func testRepeatedOnDemandSnapshotsRemainCurrentStateOnly() async {
        let provider = DiagnosticsCountingProvider()
        let service = UsageService(providers: [provider])

        let first = await service.providerDiagnostics()
        let second = await service.providerDiagnostics()
        let counts = await provider.counts

        XCTAssertEqual(first.count, 1)
        XCTAssertEqual(second.count, 1)
        XCTAssertEqual(counts.fetches, 0)
        XCTAssertEqual(counts.diagnostics, 2)
    }
}

private actor DiagnosticsCountingProvider: UsageProvider {
    nonisolated let id = ProviderID.codex
    private var fetchCount = 0
    private var diagnosticCount = 0

    var counts: (fetches: Int, diagnostics: Int) {
        (fetchCount, diagnosticCount)
    }

    func fetchUsage() async throws -> ProviderUsageSnapshot {
        fetchCount += 1
        return ProviderUsageSnapshot(
            providerID: id,
            windows: [],
            capturedAt: .now,
            source: UsageSource(kind: .mock, label: "Test", documentationURL: nil)
        )
    }

    func runtimeDiagnostic() async -> ProviderRuntimeDiagnostic {
        diagnosticCount += 1
        return ProviderRuntimeDiagnostic(
            hostApplication: nil,
            runtimeSource: .standaloneCodex,
            runtimeDetected: true,
            compatibilityStatus: .unverified,
            appServerState: .notStarted,
            lastFailureCategory: nil
        )
    }
}
