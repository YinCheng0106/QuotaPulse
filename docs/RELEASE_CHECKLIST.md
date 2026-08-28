# QuotaPulse v0.1.0 Release Checklist

Last audited: 2026-08-28

Status labels:

- **AUTO** — completed by an automated or command-line check during the release-readiness audit
- **MANUAL** — requires a person to verify the installed or distributed app
- **BLOCKED** — must be resolved before a public v0.1.0 release
- **DEFERRED** — intentionally postponed and must remain documented as a limitation
- **OPTIONAL** — additional confidence work that does not block the current release candidate

## Build

- [x] **AUTO** Clean Debug build succeeds with Xcode 26.6 on macOS 26.6.2.
- [x] **AUTO** Clean Release build succeeds with Xcode 26.6 on macOS 26.6.2.
- [x] **AUTO** No compiler, linker, or production localization warnings are emitted by either clean build.
- [x] **AUTO** Built Info.plist contains `CFBundleIdentifier=dev.quotapulse.app`, version `0.1.0`, build `1`, `LSUIElement=true`, and minimum macOS `14.0`.

## Tests

- [x] **AUTO** Complete suite passes: 159 passed, 0 failed, 1 explicitly opt-in live-notification test skipped in the normal run.
- [x] **AUTO** The opt-in live system notification test passes separately and removes its delivered test notification.
- [x] **AUTO** Process timeout, cancellation, reconnect, reap, pipe cleanup, refresh coalescing, notification deduplication, settings migration, and provider isolation tests pass.

## Runtime

- [x] **AUTO** Release smoke launch selects the ChatGPT-integrated Codex runtime and keeps exactly one app-server child owned by the single QuotaPulse instance.
- [x] **AUTO** Release binary does not contain the audited DEBUG diagnostics, development menu, or test-notification strings.
- [x] **AUTO** Runtime source review confirms one refresh task, bounded backoff, sequential providers, cancellation propagation, observer cleanup, bounded process output, and explicit pipe/file-handle shutdown.
- [ ] **OPTIONAL** Repeat an 8-hour and 24-hour Release soak on the exact downloadable artifact, if one is provided; the recorded one-hour audit is the current evidence.

## Privacy

- [x] **AUTO** Source, configuration, documentation, tests, fixtures, and repository artifacts were scanned for common API keys, tokens, credentials, private keys, prompt/session dumps, and sensitive raw provider output; no committed secret material was found.
- [x] **AUTO** Production provider errors are normalized before presentation and stderr/raw provider payloads are not logged.
- [x] **AUTO** Claude reads only the QuotaPulse-owned bounded snapshot and rejects symlinks, named pipes, oversized data, and unsupported schemas.
- [x] **AUTO** Codex does not read `~/.codex/auth.json`, session logs, or provider credentials.

## Notifications

- [x] **AUTO** Authorization, denied permission, stale data, reset generation, threshold mapping, short/weekly windows, cancellation, persistence bounds, localization, and deduplication tests pass.
- [x] **AUTO** A real local test notification was scheduled, delivered, verified, and removed through the opt-in system test.
- [x] **AUTO** Development-only notification controls are excluded from Release.
- [ ] **MANUAL** Confirm the exact downloadable app, if provided, requests permission and presents a banner/sound on a clean macOS user profile.

## Settings

- [x] **AUTO** Provider enablement, reminder thresholds, migration, persistence, and Launch at Login state mapping tests pass.
- [x] **AUTO** Launch at Login UI state is re-read from `SMAppService.mainApp.status` after both successful and failed register/unregister calls; registration failure cannot be presented as enabled.
- [ ] **MANUAL** Open the final installed app's Settings and verify controls persist after relaunch.
- [ ] **MANUAL** Enable and disable Launch at Login from an app installed in its final location, relaunch macOS, and verify system state both times.

## Localization

- [x] **AUTO** String Catalog contains 98 keys; English resolves all 98 and Traditional Chinese resolves 96 plus the two intentionally unchanged proper nouns `Codex` and `QuotaPulse`.
- [x] **AUTO** No malformed placeholder signatures were found between English and Traditional Chinese.
- [x] **AUTO** Tests cover supported locale percentage, duration, threshold, provider status, and notification formatting.
- [x] **AUTO** Release bundle contains only the intended English and Traditional Chinese localization resources.

## Accessibility

- [x] **AUTO** Source-level practical review confirms native labeled buttons/toggles, an accessibility hint for refresh, textual status alongside color, native Settings labels, and no animation-only status.
- [ ] **MANUAL** Verify the menu and Settings with VoiceOver, including provider state, quota percentage, reset time, refresh, Settings, and Quit.
- [ ] **MANUAL** Verify full keyboard access and focus order.
- [ ] **MANUAL** Verify light mode, dark mode, increased contrast, and the fixed narrow menu layout on the final build.

## Signing and notarization

- [ ] **DEFERRED** Configure and archive with an appropriate Developer ID Application identity.
- [ ] **DEFERRED** Enable and validate Hardened Runtime on the signed artifact, including live Codex child-process behavior.
- [ ] **DEFERRED** Verify the signed artifact has no `com.apple.security.get-task-allow` entitlement.
- [ ] **DEFERRED** Submit for notarization, staple the ticket, and verify with Gatekeeper on a clean Mac.
- [x] **AUTO** No App Sandbox entitlement is present; this matches the documented direct-distribution assumption and local provider access model.
- [x] **AUTO** README and release notes identify the initial v0.1.0 release as source-only and do not offer an unverified binary download.

## Repository

- [x] **AUTO** Added `.gitignore` rules for `.DS_Store`, DerivedData/build output, `.xcresult`, and Xcode per-user state.
- [x] **AUTO** No tracked archives, packages, object files, libraries, logs, diagnostics, security-scan output, or temporary files were found.
- [x] **AUTO** Created the initial Git commit as the public repository baseline.
- [x] **AUTO** Added the selected MIT License at the repository root.
- [ ] **MANUAL** Rename the mistakenly created public repository from `QuotePulse` to `QuotaPulse`, update `origin`, and verify the README clone URL before tagging.
- [ ] **DEFERRED** Add and configure the production App Icon asset; it remains an explicit release follow-up.

## Documentation

- [x] **AUTO** README describes the current v0.1 scope, keeps Claude Code explicitly Experimental/Unverified, and documents deferred distribution work.
- [x] **AUTO** Added minimal `CONTRIBUTING.md`, `SECURITY.md`, and `CHANGELOG.md`.
- [x] **AUTO** Added concise draft GitHub release notes under `docs/RELEASE_NOTES_v0.1.0.md`.
- [x] **AUTO** Known architecture and provider limitations remain documented without implying Claude subscribed-account validation.
- [x] **AUTO** GitHub Private Vulnerability Reporting is enabled and the public repository exposes **Report a vulnerability**.
- [ ] **DEFERRED** Add real README screenshots later; the current README uses a textual placeholder and has no broken image links.

## Manual checks

- [ ] **MANUAL** If a downloadable build is attached, test that exact build on a clean macOS 14-or-later account with no prior QuotaPulse preferences.
- [ ] **MANUAL** Verify Codex states for supported, missing runtime, logged-out, offline, timeout, and recovery scenarios without exposing raw errors.
- [ ] **MANUAL** Confirm Settings, notification permission, notification delivery, Launch at Login, relaunch, and Quit on the exact downloadable build, if provided.
- [ ] **MANUAL** Confirm exactly one QuotaPulse-owned app-server exists when healthy and none remains after Quit.
- [ ] **DEFERRED** Before attaching a future build, document and verify its Gatekeeper approval flow after download quarantine.
- [ ] **OPTIONAL** Validate additional ChatGPT/Codex runtime versions and both Apple silicon and Intel hardware where support is intended.
- [ ] **OPTIONAL** Validate Claude Code with a real eligible subscribed account only after the opt-in bridge is separately reviewed; keep it Experimental/Unverified until then.

## Release

- [ ] **MANUAL** Resolve the GitHub repository naming mismatch and re-check the public clone URL.
- [x] **MANUAL** Reviewed the final diff; it contains only public release documentation and repository-guidance updates.
- [x] **AUTO** The initial v0.1.0 release is source-only; no app bundle, DMG, package, or checksum is approved for attachment.
- [ ] **DEFERRED** Before any future binary release, archive and smoke-test the exact artifact, validate signing/notarization and Gatekeeper behavior, and produce a checksum.
- [ ] **MANUAL** Replace `Unreleased` in `CHANGELOG.md` with the release date.
- [ ] **MANUAL** Create the `v0.1.0` tag and publish the release only after explicit maintainer approval.
