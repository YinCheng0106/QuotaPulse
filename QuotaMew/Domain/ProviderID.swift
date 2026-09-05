import Foundation

enum ProviderID: String, CaseIterable, Codable, Identifiable, Sendable {
    case codex
    case claude

    var id: Self { self }

    var displayName: String {
        switch self {
        case .codex:
            "Codex"
        case .claude:
            "Claude Code"
        }
    }

    var systemImageName: String {
        switch self {
        case .codex:
            "terminal"
        case .claude:
            "sparkles"
        }
    }
}
