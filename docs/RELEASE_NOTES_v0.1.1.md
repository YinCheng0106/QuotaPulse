# QuotaPulse v0.1.1

QuotaPulse v0.1.1 is a reliability-focused patch release. It improves menu bar recovery and provider lifecycle behavior without adding new product features.

## Highlights

- Disabled providers no longer appear in the Dashboard or participate in background refresh work.
- Provider enablement changes are handled more reliably while a refresh is already in progress.
- QuotaPulse provides a clearer recovery path if its menu bar item has been hidden.

## Provider lifecycle reliability

Disabling a provider now fully removes it from active Dashboard and refresh behavior. Re-enabling a provider works reliably even when another refresh is in progress.

Rapid provider toggling no longer allows stale cleanup work to remove notifications created for the newer provider state.

## Menu bar recovery

QuotaPulse now provides an explicit recovery path when it has been hidden or removed from the menu bar. macOS still ultimately controls whether a third-party item is visible in the menu bar; QuotaPulse cannot override Control Center or System Settings.

## Notification and refresh reliability

Notification state is handled more safely across app restarts, and refresh scheduling covers an edge case where notification evaluation overlaps a refresh deadline.

## Distribution

QuotaPulse v0.1.1 remains source-only. No signed or notarized binary, downloadable `.app`, DMG, installer, or official Homebrew Cask is provided.

## Known limitations

- macOS 14 or later is required.
- Apple silicon is validated; Intel Macs have not been validated.
- Codex integration relies on ChatGPT.app bundled runtime behavior that may change.
- Claude Code remains Experimental / Unverified.
- Installation is from source only; Developer ID signing and notarization remain deferred.
- Production branding refinement and README screenshots remain deferred.

See the [README](../README.md) for build-from-source instructions and the complete privacy and compatibility notes.
