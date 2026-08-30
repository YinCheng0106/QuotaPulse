# Contributing to QuotaPulse

QuotaPulse targets macOS 14 or later and uses Swift 6. Build it with Xcode that includes a Swift 6 toolchain and the macOS 14 SDK or later; v0.1.0 was verified with Xcode 26.6. Apple silicon is the currently validated development platform; Intel Macs are not yet validated.

## Build and test

Open `QuotaPulse.xcodeproj` in Xcode, or run:

```sh
xcodebuild \
  -project QuotaPulse.xcodeproj \
  -scheme QuotaPulse \
  -destination 'platform=macOS,arch=arm64' \
  build

xcodebuild \
  -project QuotaPulse.xcodeproj \
  -scheme QuotaPulse \
  -destination 'platform=macOS,arch=arm64' \
  test
```

## Expectations

- Read [AGENTS.md](AGENTS.md), [ARCHITECTURE.md](ARCHITECTURE.md), and [ROADMAP.md](ROADMAP.md) before changing architecture or provider integrations.
- Keep pull requests focused, add tests for behavior changes, and report automated, manual, and unverified checks separately.
- Use Conventional Commits in English.
- Do not add accounts, cloud sync, analytics, or third-party runtime dependencies without explicit project approval.

## Provider privacy

Never include credentials, tokens, prompts, conversations, provider payloads, transcripts, coding history, repository identities, or private filesystem paths in issues, fixtures, logs, or commits. Provider integrations must use bounded inputs, normalize data before it reaches the UI, and preserve the privacy rules in [AGENTS.md](AGENTS.md).

Report vulnerabilities according to [SECURITY.md](SECURITY.md), not through a public issue.

## Provider compatibility issues

For a provider compatibility report, open **QuotaPulse Settings → Diagnostics**, select **Copy Diagnostics**, and paste the generated English report into the issue. The report is generated from a typed allowlist and is intended to replace requests for broad logs.

Do not attach app-server stdout or stderr, authentication files, Codex sessions, provider JSON, home-directory paths, prompts, source code, or repository metadata. If the built-in report is insufficient, describe the visible behavior and reproduction steps without adding private data.
