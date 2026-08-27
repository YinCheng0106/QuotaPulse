# QuotaPulse

[English](README.md) | [繁體中文](README.zh-TW.md)

QuotaPulse 是一款採用 MIT License 的開放原始碼原生 macOS 選單列 App，用來監看 AI 程式開發代理工具的使用額度與重設時間。

> 專案狀態：QuotaPulse 現為 v0.1.0 release candidate。原生選單列 UI、ChatGPT 整合的 Codex runtime、provider 架構、刷新生命週期、通知、設定、本地化與最終效能稽核都已完成。公開散布仍受正式 App Icon、Developer ID 簽章、hardened runtime 驗證與 notarization 阻擋。Claude Code 因 opt-in status-line bridge 與真實訂閱帳號驗證尚未完成，維持標示為 Experimental／Unverified。

第一個版本聚焦 OpenAI Codex 與 Claude Code。長期目標是 **Reset Intelligence**：針對暫時性或全域額度重設，提供可信且保留原始來源連結的提醒；當重設將近且仍有大量未使用額度時，也能通知使用者。

## Milestone 1

目前 App 提供：

- 使用 `MenuBarExtra(.window)` 的純選單列 SwiftUI App
- 與 provider 無關的 Codex 與 Claude Code 卡片
- 已使用百分比、剩餘百分比、重設時間與分鐘級倒數
- 各 provider 的相對最後更新時間，以及明確的載入中、過期、無法偵測、尚未設定、無法取得與安全錯誤狀態
- 後續刷新失敗時，仍保留並顯示記憶體中的上一份有效用量
- 支援 Command-R 手動刷新，以及由單一排程負責的保守 15 分鐘背景刷新
- 選單開啟時先顯示 cached snapshot，資料超過約 3 分鐘才非阻塞地背景刷新
- 暫時性 provider 失敗採有上限的 1／2／5／15／30 分鐘退避
- 與 provider 無關的 `UsageProvider` 邊界
- 可合併重複請求、防止刷新工作重疊的協調器
- 依視窗長度、隨既有刷新評估的本機 reset notifications：6 小時以下視窗使用 1 小時／30 分鐘，長視窗在門檻不超過視窗長度時使用 24／6／1 小時，並維持有上限、跨重啟的去重
- 可獨立測試的通知 policy 與原生 UserNotifications 邊界
- 提供 Launch at Login、provider 啟用狀態與 reset reminders 的精簡原生 Settings scene
- 涵蓋 domain 格式化、多 provider、錯誤隔離、刷新行為與 service 邊界的 XCTest

App 仍沒有帳號、後端、雲端儲存或第三方相依套件；preferences 與筆數有上限的通知去重 metadata 都存於 UserDefaults。Production assembly 使用本機 Codex 與 Claude Code adapters；SwiftUI previews 則維持使用自足的固定 mock providers。

Provider 資料來源研究與 adapter 行為記錄於 [docs/providers/codex.md](docs/providers/codex.md) 與 [docs/providers/claude-code.md](docs/providers/claude-code.md)。

長時間 process、refresh、reconnect、UI lifecycle 與通知驗證步驟記錄於 [docs/RUNTIME_TESTING.md](docs/RUNTIME_TESTING.md)；可量測的驗收預算仍以 [docs/PERFORMANCE.md](docs/PERFORMANCE.md) 為準。

## 系統需求與建置

- macOS 14 以上
- 含 macOS 14 SDK 以上版本的 Xcode

使用 Xcode 開啟 `QuotaPulse.xcodeproj`，或執行：

```sh
xcodebuild \
  -project QuotaPulse.xcodeproj \
  -scheme QuotaPulse \
  -destination 'platform=macOS,arch=arm64' \
  build
```

執行單元測試：

```sh
xcodebuild \
  -project QuotaPulse.xcodeproj \
  -scheme QuotaPulse \
  -destination 'platform=macOS,arch=arm64' \
  test
```

本機建置目前使用自動 Apple Development signing。儲存庫內的 Release 設定不是可散布成品；Developer ID 簽章、hardened runtime、移除開發用簽章 entitlement 與 notarization 仍須人工設定並驗證。

## v0.1 MVP

QuotaPulse v0.1 刻意維持小範圍：

- 原生 Swift 與 SwiftUI macOS 選單列 App
- Codex 與 Claude Code provider 卡片
- 每個額度視窗的已使用百分比、剩餘百分比、重設時間與倒數
- 共用 protocol 後方的 provider adapters
- 本機通知架構
- 僅限本機設定

MVP 不包含帳號、雲端同步、iPhone App、web view、遠端 Reset Intelligence 後端，也不支援 Gemini CLI 與 OpenCode。

## 工程原則

- 讓閒置 CPU 接近 0%；50 MB 以下閒置記憶體是最佳化目標，不是未量測就宣稱達成的數字。
- 優先採用事件驅動更新、手動刷新、保守的 15 分鐘週期與資料過期檢查，避免頻繁輪詢。
- 同一時間只允許一個刷新作業。
- 不掃描完整程式開發歷史目錄，也不把大型 transcript 檔案整份載入記憶體。
- 有官方本機整合介面時，不讀取或複製 provider 憑證。
- 不上傳 prompt、原始碼、程式開發歷史或本機用量紀錄。
- 未來的遠端額度重設公告資料，必須與本機用量蒐集分離。

## 技術組合

- Swift 6
- SwiftUI 與 `MenuBarExtra`
- 使用 `@Observable` 的 Observation
- `UserNotifications`
- Foundation
- XCTest
- 無第三方 runtime 相依套件

## Provider 資料來源

Codex 與 Claude Code 資料來源都已透過 `UsageProvider` 與 `UsageService` 接入。Claude Code 仍須經過另行審查、由使用者明確啟用的 status-line bridge，才能產生本機 snapshot。

| Provider | v0.1 優先資料來源 | 狀態 | 重要限制 |
| --- | --- | --- | --- |
| Codex | 官方 `codex app-server` stdio protocol 與 `account/rateLimits/read` | 已透過共用 provider 架構接入 | 優先使用 ChatGPT.app 整合的 Codex runtime，舊 Codex.app 與獨立 CLI 保留為相容性 fallback |
| Claude Code | 由使用者明確同意的 bridge，把官方 status-line `rate_limits` JSON 寫入 QuotaPulse 自有本機 snapshot | Experimental snapshot reader 已接入；bridge setup 與訂閱帳號實測待完成 | 僅適用符合資格且已完成一次 API response 的 Claude.ai 訂閱者；設定流程必須保留既有 status-line command |

Codex session JSONL 是未文件化且可能過期的備援，不是主要 contract。Claude transcript JSONL 與 `stats-cache.json` 不是可靠的訂閱額度來源，因此不會掃描。

架構、隱私邊界、資料來源評估與待決事項請參閱 [ARCHITECTURE.md](ARCHITECTURE.md)；里程碑範圍請參閱 [ROADMAP.md](ROADMAP.md)。

## 參考來源

- [Codex App Server](https://developers.openai.com/codex/app-server)
- [Codex developer commands and status-line limits](https://developers.openai.com/codex/cli/slash-commands)
- [Claude Code status-line data](https://code.claude.com/docs/en/statusline)
- [Claude Code usage-limit guidance](https://code.claude.com/docs/en/errors#usage-limits)
- [Apple `MenuBarExtra`](https://developer.apple.com/documentation/swiftui/menubarextra)
- [Apple UserNotifications](https://developer.apple.com/documentation/usernotifications)

## 貢獻與授權

請參閱 [CONTRIBUTING.md](CONTRIBUTING.md)、[SECURITY.md](SECURITY.md)、[CHANGELOG.md](CHANGELOG.md) 與 [AGENTS.md](AGENTS.md)。QuotaPulse 採用 [MIT License](LICENSE) 授權。
