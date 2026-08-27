import Foundation

struct ProviderUsageSnapshot: Equatable, Sendable {
    let providerID: ProviderID
    let windows: [UsageWindow]
    let capturedAt: Date
    let source: UsageSource
}
