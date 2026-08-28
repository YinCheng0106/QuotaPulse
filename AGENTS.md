# AGENTS.md

These instructions apply to the entire QuotaPulse repository.

## Project state

QuotaPulse is a native macOS menu bar app for monitoring AI coding-agent quota windows. Read `README.md`, `README.zh-TW.md`, `ARCHITECTURE.md`, and `ROADMAP.md` before making architectural or provider-integration changes.

QuotaPulse v0.1 functionality is complete. Production assembly uses the Codex app-server-backed provider and the Claude Code QuotaPulse-owned snapshot reader through normalized provider state; SwiftUI previews remain mock-only. The Claude opt-in status-line bridge and live subscribed-account validation are not implemented, so Claude Code remains Experimental / Unverified. Do not jump directly to bridge installation, Reset Intelligence, cloud services, or release automation unless the user explicitly changes scope.

## Language and naming

- Respond to the user in Traditional Chinese (Taiwan).
- Use Taiwanese terminology where practical.
- Keep source code, identifiers, file names, code comments, and Git commit messages in English unless localization content requires another language.
- Keep `AGENTS.md` and `README.md` in English for international contributors.
- Keep `README.zh-TW.md`, `ARCHITECTURE.md`, and `ROADMAP.md` in Traditional Chinese (Taiwan).
- Write provider research under `docs/providers/` primarily in Traditional Chinese while preserving API names, paths, class names, and code identifiers in English.
- Use Conventional Commits in English when explicitly asked to commit.

## Product boundaries

v0.1 includes:

- macOS menu bar app
- Codex and Claude Code provider cards
- usage, remaining percentage, reset time, and countdown
- provider adapters, local settings, and local notification architecture

v0.1 excludes:

- accounts and cloud sync
- iOS apps
- Electron, Flutter, and web views
- remote Reset Intelligence services
- Gemini CLI and OpenCode implementation
- historical coding analytics

Do not infer permission to expand these boundaries.

## Technology rules

- Use Swift, SwiftUI, `MenuBarExtra`, `UserNotifications`, and Foundation.
- Prefer native APIs and minimal dependencies.
- Do not add a third-party runtime dependency without explicit approval and a documented size, privacy, maintenance, and licensing rationale.
- The deployment target is macOS 14+ for the current implementation. Treat broader compatibility as a separate product decision.
- Use `@Observable` with `@MainActor` for new UI-owned reference models when the deployment target supports it. View-owned observable models use private `@State`.
- Keep SwiftUI view bodies free of file I/O, process launching, decoding, sorting, and other heavy work.
- Use stable identities in `ForEach` and dedicated subviews with narrow value inputs.
- Use `Button` for actions and provide accessibility labels and values.
- Keep AppKit bridging minimal and justified.

## Architecture boundaries

- UI depends on normalized domain models, never provider DTOs.
- Provider-specific parsing lives under `Providers/<Provider>/`.
- `UsageProvider` is the integration boundary for local quota sources.
- `UsageService` coordinates adapters; it does not render UI or schedule notifications.
- `NotificationService` and `SettingsService` remain independently testable.
- Future `ResetEventService` is separate from `UsageProvider`, local snapshots, and local settings.
- Do not add speculative empty implementations for future services merely to mirror the architecture document.

## Provider-source rules

### Codex

- Prefer the documented `codex app-server` stdio protocol and `account/rateLimits/read`.
- Let Codex own authentication. Never parse or copy `~/.codex/auth.json`.
- Do not screen-scrape interactive `/status` output.
- Treat session JSONL rate-limit events as an undocumented, stale-prone fallback only.
- Any fallback reader must use bounded incremental reads and discard all unrelated content immediately.

### Claude Code

- Prefer the documented status-line `rate_limits` fields through an explicit opt-in local snapshot bridge.
- Persist only rate-limit windows, bridge schema version, Claude version when available, and capture time.
- Never persist status-line workspace, repository, transcript, session, token, cost, model, or unknown fields.
- Never scan `~/.claude/projects` transcripts or use `stats-cache.json` as subscription quota.
- Never access Claude credentials or undocumented OAuth usage endpoints.
- Never silently replace an existing `statusLine.command`; setup must be previewable and reversible.

If a provider contract is uncertain, fail as unavailable or unsupported and document the uncertainty. Do not fabricate usage percentages, reset times, plan limits, or successful integrations.

## Privacy and security

- Never upload prompts, source code, coding history, local paths, repository identity, transcripts, or usage snapshots.
- Never log credentials, raw provider payloads, full command output, or transcript lines.
- Redact sensitive paths and provider error bodies before presenting or logging them.
- Store only the minimum normalized local data needed for the UI.
- Keep future announcement-network requests free of local usage and workspace metadata.
- Every future Reset Intelligence event must preserve a clickable original source URL and publisher metadata.
- Use bounded reads, bounded process output, explicit timeouts, and atomic snapshot writes.

## Performance and concurrency

- Idle CPU should be close to 0%; idle memory below 50 MB is an optimization target that must be measured in a Release build.
- Do not use global one-second timers. Derive visible countdowns at minute granularity.
- Do not poll continuously by default.
- Maintain one refresh task; coalesce overlapping refresh requests.
- Refresh providers sequentially unless measurement justifies bounded concurrency.
- Cancel owned tasks on shutdown and close every process pipe and file handle.
- Do not keep provider child processes alive between refreshes without profiling and explicit justification.
- Do not load complete large logs into memory. Prefer documented small snapshots and bounded incremental parsing.

## Testing and validation

- Start provider work from redacted fixtures and protocol tests.
- Cover malformed, partial, stale, oversized, and future-version payloads.
- Test refresh coalescing, cancellation, timeout, and process cleanup.
- Inject notification and persistence boundaries so tests do not require live system state.
- Use self-contained SwiftUI previews with mock data only.
- After visible UI changes, verify menu layout, light/dark mode, keyboard access, VoiceOver semantics, and narrow widths.
- Before performance claims, profile a Release build with Activity Monitor or Instruments and record the measurement conditions.
- Distinguish compilation, unit tests, UI checks, live provider checks, notification delivery, signing, notarization, and distribution. Passing one does not prove the others.

## Repository hygiene

- Inspect `git status` before editing.
- Preserve unrelated user changes and untracked files.
- Keep changes scoped and low churn.
- Use `apply_patch` for manual file edits.
- Do not stage, commit, amend, push, tag, publish, or create a release without explicit user approval.
- When commits are requested, use Conventional Commits such as `feat(app): add menu bar shell`.

## Documentation discipline

- Update `ARCHITECTURE.md` when a provider contract, privacy boundary, platform baseline, or distribution model changes.
- Update `ROADMAP.md` only when milestone scope or verified status changes.
- Keep README status honest; do not describe planned features as implemented.
- Link claims about provider interfaces to official OpenAI, Anthropic, or Apple documentation.
- Mark undocumented behavior as experimental and include a fallback or failure state.
