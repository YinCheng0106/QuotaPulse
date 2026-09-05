protocol UsageProvider: Sendable {
    var id: ProviderID { get }
    func fetchUsage() async throws -> ProviderUsageSnapshot
    func runtimeDiagnostic() async -> ProviderRuntimeDiagnostic
}

extension UsageProvider {
    func runtimeDiagnostic() async -> ProviderRuntimeDiagnostic {
        .unknown
    }
}

protocol ProviderStatusProvidingError: Error, Sendable {
    var providerStatus: ProviderStatus { get }
}
