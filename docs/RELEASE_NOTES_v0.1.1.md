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

<details>
<summary>繁體中文（台灣）</summary>

## QuotaPulse v0.1.1

QuotaPulse v0.1.1 是著重於可靠性的修補版本。此版本改善了選單列復原與供應商生命週期的行為，未新增產品功能。

### 重點功能

- 已停用的供應商不再顯示於 Dashboard，也不會參與背景重新整理作業。
- 即使重新整理作業已在進行中，供應商啟用狀態的變更也能更可靠地處理。
- 當 QuotaPulse 的選單列項目被隱藏時，現在提供更明確的復原方式。

### 供應商生命週期可靠性

停用供應商後，該供應商現在會完全從作用中的 Dashboard 與重新整理行為中移除。即使另一項重新整理作業進行中，重新啟用供應商也能可靠地運作。

快速切換供應商開關時，過時的清理作業不再可能移除為較新供應商狀態建立的通知。

### 選單列復原

當 QuotaPulse 已被隱藏或從選單列移除時，現在提供明確的復原方式。是否顯示第三方項目仍由 macOS 最終決定；QuotaPulse 無法覆寫控制中心或系統設定。

### 通知與重新整理可靠性

跨應用程式重新啟動時，通知狀態現在會以更安全的方式處理；重新整理排程也涵蓋通知評估與重新整理截止時間重疊的邊緣案例。

### 發行方式

QuotaPulse v0.1.1 仍僅提供原始碼。未提供已簽署或完成公證的二進位檔、可下載的 `.app`、DMG、安裝程式，或官方 Homebrew Cask。

### 已知限制

- 需要 macOS 14 或以上版本。
- 已驗證 Apple silicon；尚未驗證 Intel Mac。
- Codex 整合依賴 ChatGPT.app 內附執行環境的行為，未來可能變更。
- Claude Code 仍為 **實驗性／尚未驗證**。
- 僅支援從原始碼安裝；Developer ID 簽署與公證仍延後處理。
- 正式品牌視覺優化與 README 螢幕截圖仍延後處理。

請參閱 [README](../README.md)，以取得從原始碼建置的說明，以及完整的隱私與相容性注意事項。

</details>
