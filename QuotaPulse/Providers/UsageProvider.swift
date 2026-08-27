protocol UsageProvider: Sendable {
    var id: ProviderID { get }
    func fetchUsage() async throws -> ProviderUsageSnapshot
}

protocol ProviderStatusProvidingError: Error, Sendable {
    var providerStatus: ProviderStatus { get }
}
