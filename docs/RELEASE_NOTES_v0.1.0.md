# QuotaPulse v0.1.0

QuotaPulse is a lightweight native macOS menu bar utility for monitoring AI coding-agent quota usage and reset times.

## Highlights

- Native Swift and SwiftUI menu bar experience
- Codex usage and remaining percentages, reset times, and countdowns
- Local reset-reminder notifications
- Settings for Launch at Login, providers, and reminder thresholds
- English and Traditional Chinese localization
- Privacy-first local processing with no QuotaPulse account or cloud service

## Provider support

Codex is supported and validated with the runtime bundled in ChatGPT.app. Compatible legacy Codex.app and standalone CLI locations remain discovery fallbacks. The ChatGPT.app runtime path is an undocumented packaging detail and may require compatibility updates after ChatGPT changes.

Claude Code is **Experimental / Unverified**. Its local snapshot reader is implemented, but the opt-in status-line bridge and validation with a real eligible subscribed account are not complete.

## Source-only release

The initial v0.1.0 GitHub release is source-only. No QuotaPulse app bundle, DMG, or installer is approved for attachment. Build the app from source using the instructions in the README.

Developer ID signing, Hardened Runtime validation, notarization, and binary-distribution checks are deferred.

## Known limitations

- macOS 14 or later; Apple silicon validated, Intel not yet validated
- Production App Icon is still pending
- No usage history, cloud sync, iPhone app, or Reset Intelligence

See the [README](../README.md) for build-from-source instructions and the complete privacy and compatibility notes.
