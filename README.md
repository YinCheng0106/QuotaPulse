# QuotaPulse

**English** | [繁體中文](README.zh-TW.md)

QuotaPulse is a lightweight native macOS menu bar utility for monitoring AI coding-agent quota usage and reset times.

## Screenshots

Real application screenshots are intentionally deferred and will be added later. The current README does not link to placeholder images.

## Why QuotaPulse

Coding-agent limits often reset on different schedules. QuotaPulse keeps the current percentage, reset time, and countdown one click away without requiring a QuotaPulse account or cloud service.

## Features

- Native Swift and SwiftUI macOS menu bar app
- Codex usage and remaining percentages
- Reset times and minute-level countdowns
- Local reset reminders through macOS notifications
- Compact Settings for Launch at Login, provider enablement, and reminder thresholds
- Privacy-safe compatibility diagnostics with a copyable GitHub issue report
- English and Traditional Chinese localization
- Conservative refresh scheduling designed for lightweight long-running use
- Local, privacy-first processing with no third-party runtime dependencies

## Supported providers

| Provider | Status | Integration |
| --- | --- | --- |
| Codex | **Supported** | Validated with the Codex runtime bundled in ChatGPT.app. Legacy Codex.app and compatible standalone CLI locations are retained as discovery fallbacks. |
| Claude Code | **Experimental / Unverified** | The bounded local snapshot reader is implemented, but the opt-in status-line bridge and validation with a real eligible subscribed account are not complete. |

ChatGPT.app support relies on an undocumented packaging detail: the bundled Codex runtime path is not a stable public contract. ChatGPT updates may therefore require QuotaPulse compatibility updates.

## Installation

### Downloaded builds

The initial v0.1.0 GitHub release is source-only. No downloadable QuotaPulse app, DMG, or package is approved for that release.

Developer ID signing, Hardened Runtime validation, notarization, and binary-distribution checks are intentionally deferred. A custom Homebrew Tap is also only a possible future installation method; no official Homebrew Cask is available today.

### Build from source

Requirements:

- macOS 14 or later
- Xcode with a Swift 6 toolchain and the macOS 14 SDK or later; v0.1.0 was verified with Xcode 26.6
- ChatGPT.app for the currently validated live Codex integration; it is not required to compile or launch the app

Clone and open the project:

```sh
git clone https://github.com/YinCheng0106/QuotaPulse.git
cd QuotaPulse
open QuotaPulse.xcodeproj
```

In Xcode, select the `QuotaPulse` scheme and **My Mac**, then choose **Product → Run**. If Xcode requests a development team for a local build, select your own team in Signing & Capabilities; this does not constitute Developer ID signing for distribution.

The equivalent command-line build is:

```sh
xcodebuild \
  -project QuotaPulse.xcodeproj \
  -scheme QuotaPulse \
  -destination 'platform=macOS,arch=arm64' \
  -configuration Debug \
  build
```

## How Codex integration works

QuotaPulse locates a compatible Codex executable, preferring the runtime bundled in ChatGPT.app and falling back to supported legacy or standalone locations. It launches `codex app-server` directly and requests `account/rateLimits/read` over the documented stdio protocol.

Codex remains responsible for authentication. QuotaPulse does not read or copy `~/.codex/auth.json`, scrape the interactive `/status` screen, or scan Codex session history. Provider data is normalized before it reaches SwiftUI.

## Notifications

Reset reminders are scheduled locally through macOS `UserNotifications` after a fresh provider refresh when at least 20% of the quota remains. Short quota windows can notify at 1 hour and 30 minutes; long windows can notify at 24 hours, 6 hours, and 1 hour when the threshold fits the window. Notifications can be disabled globally or by threshold in Settings.

QuotaPulse also compares bounded normalized provider state across refreshes to detect a genuine new quota cycle and can notify once when that window has refreshed. Percentage decreases alone do not count as resets, and persisted cycle identity prevents duplicate notifications after restart. Official external Reset Intelligence feeds are a future phase; see [docs/RESET_INTELLIGENCE.md](docs/RESET_INTELLIGENCE.md).

## Privacy

QuotaPulse processes usage data locally and does not require a QuotaPulse account, backend, analytics service, or cloud sync. It is designed not to intentionally upload:

- prompts or conversation contents
- source code or coding history
- authentication credentials
- provider session contents

For Codex, QuotaPulse sends only the app-server protocol requests needed to obtain rate-limit data to the locally installed runtime; that runtime performs its normal provider communication and authentication. For Claude Code, the implemented reader accepts only a small, versioned QuotaPulse-owned snapshot and does not scan transcripts, history, credentials, or internal usage caches.

These statements describe QuotaPulse's implementation boundary. They do not override the privacy or network behavior of ChatGPT, Codex, Claude Code, macOS, or other software running on the Mac.

## Performance philosophy

QuotaPulse favors event-driven updates, a conservative refresh cadence, bounded process output, and one coalesced refresh at a time. Countdown presentation does not trigger provider requests.

In approximately one hour of development-machine testing, QuotaPulse idle memory remained around 48 MB. Opening the menu or Settings temporarily reached about 70 MB, and refreshes temporarily added roughly 10–20 MB before returning toward baseline. Idle CPU was observed near zero. These are observations from one development environment, not universal guarantees. See [docs/PERFORMANCE.md](docs/PERFORMANCE.md) for conditions and limitations.

## Provider compatibility troubleshooting

If provider usage becomes unavailable, open **Settings → Diagnostics** and select **Copy Diagnostics**. Paste the English report into the GitHub issue. The report contains only allowlisted version, system, provider, runtime, connection, refresh, and metadata-availability fields; it excludes credentials, prompts, sessions, project data, private paths, raw provider responses, and exact quota percentages.

Do not attach raw app-server output, Codex session files, authentication files, or broad system logs.

## Known limitations

- Requires macOS 14 or later
- Validated on Apple silicon; Intel Macs are not yet validated
- ChatGPT.app Codex runtime discovery depends on an undocumented bundle path
- Claude Code support is Experimental / Unverified
- The initial v0.1.0 release is source-only; downloadable binary distribution is not yet validated
- No usage history or cloud sync
- No iPhone app
- Official external Reset Intelligence feed ingestion is not implemented

## Roadmap

QuotaPulse now includes local reset-cycle detection. Future work may include a reviewed Claude Code opt-in bridge, broader provider and hardware validation, signed/notarized distribution, and source-linked official Reset Intelligence feed ingestion. These future items are not implemented claims. See [ROADMAP.md](ROADMAP.md).

## Contributing

Focused contributions are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md), [SECURITY.md](SECURITY.md), and [ARCHITECTURE.md](ARCHITECTURE.md) before opening a pull request.

## License

QuotaPulse is licensed under the [MIT License](LICENSE).
