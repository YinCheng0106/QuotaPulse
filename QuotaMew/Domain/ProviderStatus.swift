import Foundation

enum ProviderFailure: Equatable, Sendable {
    case refreshFailed
    case runtimeLaunchFailed
    case usageUnavailable
}

enum ProviderStatus: Equatable, Sendable {
    case loading
    case available
    case disabled
    case stale
    case notConfigured
    case notInstalled
    case unsupportedAuthentication
    case failed(ProviderFailure)
}

struct ProviderState: Identifiable, Equatable, Sendable {
    let providerID: ProviderID
    let status: ProviderStatus
    let snapshot: ProviderUsageSnapshot?

    var id: ProviderID { providerID }

    var lastUpdatedAt: Date? { snapshot?.capturedAt }

    static func loading(
        _ providerID: ProviderID,
        snapshot: ProviderUsageSnapshot? = nil
    ) -> Self {
        Self(providerID: providerID, status: .loading, snapshot: snapshot)
    }
}
