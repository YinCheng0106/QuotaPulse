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
- No usage history, cloud sync, iPhone app, or Reset Intelligence

See the [README](../README.md) for build-from-source instructions and the complete privacy and compatibility notes.

<details>
<summary>繁體中文（台灣）</summary>

QuotaPulse 是一款輕量的原生 macOS 選單列工具程式，用於監控 AI 程式設計代理工具的用量額度與重設時間。

## 重點功能

- 原生 Swift 與 SwiftUI 選單列操作體驗
- 顯示 Codex 用量與剩餘百分比、重設時間及倒數計時
- 本機重設提醒通知
- 可設定登入時啟動、供應商與提醒門檻
- 支援英文與繁體中文在地化
- 以隱私優先為原則的本機處理，不需 QuotaPulse 帳號或雲端服務

## 供應商支援

Codex 已支援，並已使用 ChatGPT.app 內附的執行環境完成驗證。相容的舊版 Codex.app 與獨立 CLI 位置仍保留為探索用的備援路徑。ChatGPT.app 執行環境路徑屬於未公開的封裝細節；ChatGPT 更新後可能需要進行相容性調整。

Claude Code 為 **實驗性／尚未驗證**。本機快照讀取器已完成實作，但需使用者明確啟用的狀態列橋接程式，以及使用真實且符合資格的訂閱帳號進行驗證，均尚未完成。

## 僅提供原始碼的版本

首個 v0.1.0 GitHub Release 僅提供原始碼。不會附上任何已核准的 QuotaPulse app bundle、DMG 或安裝程式。請依 README 中的說明，從原始碼建置應用程式。

Developer ID 簽署、Hardened Runtime 驗證、公證（notarization）及二進位發行檢查均延後處理。

## 已知限制

- 需 macOS 14 或以上版本；已驗證 Apple silicon，尚未驗證 Intel Mac
- 尚未提供用量歷史紀錄、雲端同步、iPhone App 或 Reset Intelligence

請參閱 [README](../README.md)，以取得從原始碼建置的說明，以及完整的隱私與相容性注意事項。

</details>
