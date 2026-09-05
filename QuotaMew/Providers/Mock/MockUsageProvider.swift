import Foundation

struct MockUsageProvider: UsageProvider {
    let id: ProviderID
    private let snapshot: ProviderUsageSnapshot

    init(snapshot: ProviderUsageSnapshot) {
        self.id = snapshot.providerID
        self.snapshot = snapshot
    }

    func fetchUsage() async throws -> ProviderUsageSnapshot {
        snapshot
    }
}

extension MockUsageProvider {
    static func codex(now: Date) -> Self {
        Self(
            snapshot: ProviderUsageSnapshot(
                providerID: .codex,
                windows: [
                    UsageWindow(
                        id: "codex-five-hour",
                        label: AppLocalization.string("5-hour window"),
                        usedPercentage: 38,
                        resetAt: now.addingTimeInterval(2 * 60 * 60 + 24 * 60),
                        duration: .seconds(5 * 60 * 60)
                    ),
                    UsageWindow(
                        id: "codex-weekly",
                        label: AppLocalization.string("Weekly window"),
                        usedPercentage: 61,
                        resetAt: now.addingTimeInterval(3 * 24 * 60 * 60 + 8 * 60 * 60),
                        duration: .seconds(7 * 24 * 60 * 60)
                    ),
                ],
                capturedAt: now,
                source: UsageSource(kind: .mock, label: "Mock data", documentationURL: nil)
            )
        )
    }

    static func claude(now: Date) -> Self {
        Self(
            snapshot: ProviderUsageSnapshot(
                providerID: .claude,
                windows: [
                    UsageWindow(
                        id: "claude-five-hour",
                        label: AppLocalization.string("5-hour window"),
                        usedPercentage: 72,
                        resetAt: now.addingTimeInterval(58 * 60),
                        duration: .seconds(5 * 60 * 60)
                    ),
                    UsageWindow(
                        id: "claude-weekly",
                        label: AppLocalization.string("Weekly window"),
                        usedPercentage: 34,
                        resetAt: now.addingTimeInterval(5 * 24 * 60 * 60 + 3 * 60 * 60),
                        duration: .seconds(7 * 24 * 60 * 60)
                    ),
                ],
                capturedAt: now,
                source: UsageSource(kind: .mock, label: "Mock data", documentationURL: nil)
            )
        )
    }
}
