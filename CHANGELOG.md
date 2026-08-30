# Changelog

All notable changes to QuotaPulse will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Provider-independent local quota reset detection with bounded restart-safe deduplication.
- Localized completed-reset notifications derived from normalized provider and window data.
- Provider-independent `ResetEvent` and future `ResetEventSource` domain boundaries.
- Privacy-safe compatibility diagnostics and an allowlisted English report for GitHub issues.

## [0.1.0] - 2026-08-28

### Added

- Native macOS menu bar app built with Swift and SwiftUI.
- Codex usage monitoring through the ChatGPT.app-integrated runtime, with compatible legacy and standalone discovery fallbacks.
- Usage percentages, reset times, and minute-level reset countdowns.
- Local reset-reminder notifications.
- Native Settings for Launch at Login, provider enablement, and notification thresholds.
- English and Traditional Chinese localization.
- Experimental / Unverified Claude Code snapshot-reader support; the opt-in bridge and subscribed-account validation are not complete.

### Security

- Provider credentials, prompts, transcripts, raw provider responses, and coding history are outside QuotaPulse's data model and logging boundary.

### License

- Released under the MIT License.

### Known limitations

- Requires macOS 14 or later; Apple silicon is validated and Intel is not yet validated.
- Developer ID signing, notarization, and the production App Icon are deferred.
- Claude Code remains Experimental / Unverified.
- Usage history, cloud sync, iPhone support, and Reset Intelligence are not included.
