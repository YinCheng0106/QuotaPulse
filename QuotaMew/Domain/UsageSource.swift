import Foundation

enum UsageSourceKind: String, Equatable, Sendable {
    case mock
    case codexAppServer
    case claudeStatusLineSnapshot
}

struct UsageSource: Equatable, Sendable {
    let kind: UsageSourceKind
    let label: String
    let documentationURL: URL?
}
