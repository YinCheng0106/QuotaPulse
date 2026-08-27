# QuotaPulse

[English](README.md) | [繁體中文](README.zh-TW.md)

QuotaPulse is an open-source, native macOS menu bar app for monitoring AI coding-agent usage limits and reset times.

> Project status: QuotaPulse is a v0.1.0 release candidate. The native menu bar UI, ChatGPT-integrated Codex runtime, provider architecture, refresh lifecycle, notifications, settings, localization, and release performance audits are complete. Public distribution is still blocked on the production app icon, Developer ID signing, hardened runtime validation, and notarization. Claude Code remains Experimental and Unverified because its opt-in status-line bridge and subscribed-account validation are not complete.

The first release focuses on OpenAI Codex and Claude Code. The longer-term goal is **Reset Intelligence**: trustworthy, source-linked warnings about temporary or global quota resets, including reminders when meaningful quota remains unused.

## Milestone 1

The current app provides:

- a menu-bar-only SwiftUI app using `MenuBarExtra(.window)`
- provider-independent cards for Codex and Claude Code
- used and remaining percentages, reset times, and minute-level countdowns
- per-provider relative last-updated times and distinct loading, stale, unavailable, not-detected, not-configured, and safe error states
- last-known in-memory usage remains visible when a later refresh fails
- manual refresh with Command-R plus a single conservative 15-minute background schedule
- non-blocking refresh on menu open when cached provider data is older than about 3 minutes
- bounded 1/2/5/15/30-minute retry backoff for transient provider failures
- a provider-independent `UsageProvider` boundary
- a coalescing refresh coordinator that prevents overlapping refresh work
- duration-aware, refresh-driven local reset notifications: 1 hour and 30 minutes for windows up to 6 hours; 24, 6, and 1 hours for long windows when those thresholds fit within the window duration
- an independently testable notification policy and native UserNotifications boundary
- a compact native Settings scene for Launch at Login, provider enablement, and reset reminders
- XCTest coverage for domain formatting, multiple providers, isolated failures, refresh behavior, and service boundaries

The app still uses no accounts, backend, cloud storage, or third-party dependencies. Preferences and bounded notification-deduplication metadata use UserDefaults. Production assembly uses the local Codex and Claude Code adapters; SwiftUI previews remain self-contained with deterministic mock providers.

Provider research and adapter behavior are documented in [docs/providers/codex.md](docs/providers/codex.md) and [docs/providers/claude-code.md](docs/providers/claude-code.md).

Long-running process, refresh, reconnect, UI lifecycle, and notification validation procedures are documented in [docs/RUNTIME_TESTING.md](docs/RUNTIME_TESTING.md); measurable acceptance budgets remain in [docs/PERFORMANCE.md](docs/PERFORMANCE.md).

## Requirements and build

- macOS 14 or later
- Xcode with the macOS 14 SDK or later

Open `QuotaPulse.xcodeproj` in Xcode, or run:

```sh
xcodebuild \
  -project QuotaPulse.xcodeproj \
  -scheme QuotaPulse \
  -destination 'platform=macOS,arch=arm64' \
  build
```

Run the unit tests with:

```sh
xcodebuild \
  -project QuotaPulse.xcodeproj \
  -scheme QuotaPulse \
  -destination 'platform=macOS,arch=arm64' \
  test
```

Local builds currently use automatic Apple Development signing. The checked Release configuration is not a distributable artifact: Developer ID signing, hardened runtime, removal of development-only signing entitlements, and notarization still require manual release configuration and validation.

## v0.1 MVP

QuotaPulse v0.1 is intentionally small:

- a native Swift and SwiftUI macOS menu bar app
- provider cards for Codex and Claude Code
- used percentage, remaining percentage, reset time, and countdown per quota window
- provider adapters behind a shared protocol
- local notification architecture
- local settings only

The MVP does not include accounts, cloud sync, an iPhone app, a web view, a remote Reset Intelligence backend, or Gemini CLI and OpenCode support.

## Engineering principles

- Keep idle CPU near 0% and treat 50 MB idle memory as an optimization target, not an unmeasured claim.
- Prefer event-driven updates, manual refresh, a conservative 15-minute cadence, and staleness checks over frequent polling.
- Allow only one refresh operation at a time.
- Never scan complete coding-history directories or load large transcript files into memory.
- Never read or copy provider credentials when an official local integration surface is available.
- Never upload prompts, source code, coding history, or local usage records.
- Keep future remote reset-announcement data separate from local usage collection.

## Stack

- Swift 6
- SwiftUI and `MenuBarExtra`
- Observation with `@Observable`
- `UserNotifications`
- Foundation
- XCTest
- no third-party runtime dependencies

## Provider sources

The Codex and Claude Code sources are connected through `UsageProvider` and `UsageService`. Claude Code still requires a separately reviewed, explicit opt-in status-line bridge before it can produce a local snapshot.

| Provider | Preferred v0.1 source | Status | Important limitation |
| --- | --- | --- | --- |
| Codex | Official `codex app-server` stdio protocol and `account/rateLimits/read` | Integrated through the shared provider architecture | Prefers the Codex runtime integrated into ChatGPT.app, with legacy Codex.app and standalone CLI compatibility fallbacks |
| Claude Code | Official status-line `rate_limits` JSON copied into a QuotaPulse-owned local snapshot by an opt-in bridge | Experimental snapshot reader integrated; bridge setup and subscribed-account validation pending | Available only for eligible Claude.ai subscribers after an API response; setup must preserve any existing status-line command |

Codex session JSONL is an undocumented, stale-prone fallback and is not the primary contract. Claude transcript JSONL and `stats-cache.json` are not reliable subscription-quota sources and will not be scanned.

See [ARCHITECTURE.md](ARCHITECTURE.md) for architecture, privacy boundaries, source assessment, and open decisions. See [ROADMAP.md](ROADMAP.md) for milestone scope.

## Source references

- [Codex App Server](https://developers.openai.com/codex/app-server)
- [Codex developer commands and status-line limits](https://developers.openai.com/codex/cli/slash-commands)
- [Claude Code status-line data](https://code.claude.com/docs/en/statusline)
- [Claude Code usage-limit guidance](https://code.claude.com/docs/en/errors#usage-limits)
- [Apple `MenuBarExtra`](https://developer.apple.com/documentation/swiftui/menubarextra)
- [Apple UserNotifications](https://developer.apple.com/documentation/usernotifications)

## Contributing and license

See [CONTRIBUTING.md](CONTRIBUTING.md), [SECURITY.md](SECURITY.md), [CHANGELOG.md](CHANGELOG.md), and [AGENTS.md](AGENTS.md). QuotaPulse is licensed under the [MIT License](LICENSE).
