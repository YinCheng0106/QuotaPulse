# QuotaPulse 架構

狀態：Milestone 1 實作基準、Codex provider core、Claude Code snapshot provider core、共用應用程式整合與 v0.1 本機 reset notifications，2026-08-26。Production `AppDependencies` 已透過 `UsageProvider` 接入兩個 adapters；SwiftUI previews 保持 mock-only。Claude opt-in status-line bridge 尚未實作。

## 1. 目標與限制

QuotaPulse v0.1 是原生 macOS 選單列工具，將 Codex 與 Claude Code 的額度視窗資料正規化，並顯示已使用額度、剩餘額度、重設時間與倒數。它不是另一個 AI agent client。

架構必須：

- 把 provider 特有行為封裝在 adapters 後方
- 讓 UI 不依賴 provider payload 與檔案配置
- 區分新鮮、過期、無法取得與不支援的資料
- 避免工作重疊與積極輪詢
- 不讀取憑證、prompt、原始碼與完整 transcript 歷史
- 不需要伺服器也能支援本機通知
- 為 Gemini CLI、OpenCode 與未來 Reset Intelligence 保留清楚邊界

v0.1 不處理帳號、雲端同步、遠端公告擷取、歷史分析、token 成本計算、自動探索憑證或 iOS companion App。

## 2. 平臺基準

- macOS 14 以上
- Swift 6 與 SwiftUI app lifecycle
- `.window` 樣式的 `MenuBarExtra`
- 原生 `Settings` scene
- `LSUIElement = true`，不顯示 Dock 圖示
- 使用 `@Observable` 並隔離於 `@MainActor`
- 無第三方 runtime 相依套件

Milestone 1 已確認 macOS 14 作為目前 deployment target。是否支援更舊版本仍是產品決策，不應在同一套程式碼維護平行的 Observation 實作。

目前規劃以 Mac App Store 外的直接簽章與 notarization 方式散布。啟動已安裝 provider 執行檔及讀取 provider 自有檔案，與直接套用 App Sandbox 的設計存在衝突；若未來要求上架 Mac App Store，必須先重新設計 provider 整合與 security-scoped access。

## 3. 系統形狀

```text
MenuBarExtra / Settings
          |
          v
  @MainActor AppModel
          |
          v
   RefreshCoordinator ------> NotificationService
          |
          v
     UsageService actor
          |
          +----> MockUsageProvider (SwiftUI previews / tests)
          |
          +----> CodexProvider -----------------------> Codex app-server
          |
          +----> ClaudeProvider ----------------------> QuotaPulse-owned snapshot
                                                       ^
                                                       |
                                      opt-in status-line bridge（尚未實作）

未來的獨立路徑：
ResetEventService ----> remote announcement sources
          |
          v
ResetEvent，保留不可變的原始來源 URL 與 publisher metadata
```

UI 只接收正規化後的 snapshot；不解析 provider payload、不啟動指令，也不讀取檔案。

## 4. Domain model

Milestone 1 已實作以下責任：

```swift
enum ProviderID: String, Codable, Sendable {
    case codex
    case claude
    // future: gemini, openCode
}

struct UsageWindow: Identifiable, Equatable, Sendable {
    let id: String
    let label: String
    let usedPercentage: Double?
    let resetAt: Date?
    let duration: Duration?
}

struct ProviderUsageSnapshot: Equatable, Sendable {
    let providerID: ProviderID
    let windows: [UsageWindow]
    let capturedAt: Date
    let source: UsageSource
}
```

支援狀態包含 `loading`、`available`、`stale`、`notConfigured`、`notInstalled`、`unsupportedAuthentication` 與 `failed`。`failed` 只攜帶正規化的 `ProviderFailure`（`refreshFailed`、`runtimeLaunchFailed`、`usageUnavailable`），不攜帶 raw error message。每個額度視窗都使用穩定 ID，因為同一 provider 可能同時提供數個視窗。

存在的百分比必須是有限數值。原始 provider 值可保留在 domain model，實際繪製 progress 時才限制於 0...100；若 provider 只回傳有效 `resetAt`，window 仍可存在，但 UI 與通知都不得補造 percentage。`resetAt` 已經過期不代表額度真的重設，也不能推論用量為零；舊 snapshot 應標示為過期，直到 provider 提供新資料。

## 5. Provider adapter contract

使用能力導向名稱，不採籠統的 `ProviderProtocol`：

```swift
protocol UsageProvider: Sendable {
    var id: ProviderID { get }
    func fetchUsage() async throws -> ProviderUsageSnapshot
}
```

此 protocol 不暴露 provider 路徑、憑證、輪詢間隔、UI 顏色或通知行為。DTO 必須留在各自 provider 資料夾，並在 adapter 邊界轉成 domain model。

`UsageService` 依序刷新 providers 並回傳正規化結果。v0.1 只有兩個 adapters，不值得用 process 層級的平行處理增加尖峰資源；只有量測證明有需要後，才可考慮受限的並行。

Milestone 1 的 `MockUsageProvider` 使用固定規則產生 Codex 與 Claude Code 測試資料，沒有讀檔、網路或 process I/O。

後續限定範圍的 Codex discovery 已實作 `CodexProvider`、`CodexAppServerClient`、DTO 與 executable locator。Claude Code discovery 已實作 `ClaudeProvider`、版本化 snapshot DTO 與 bounded snapshot reader，但沒有 bridge installer。Production `AppDependencies` 以 `[any UsageProvider]` 建立兩者，再由 `UsageService` 依序刷新；SwiftUI 只接收 `ProviderState` 與 `ProviderUsageSnapshot`。完整調查與 fallback policies 記錄於 `docs/providers/codex.md` 與 `docs/providers/claude-code.md`。

## 6. Codex 資料來源評估

### 優先方案：有文件的 Codex App Server

[官方 Codex App Server](https://learn.chatgpt.com/docs/app-server) 透過 stdio 提供 newline-delimited JSON。目前 client：

1. 不經 shell，依序從標準位置與 `NSWorkspace` 發現的 ChatGPT.app 整合 runtime、舊 Codex.app、常見 CLI locations 與 GUI process 的受限 `PATH` 尋找 `codex` 執行檔
2. 使用 `Process` 啟動 `codex app-server`
3. 傳送含 QuotaPulse client metadata 的 `initialize`
4. 傳送 `initialized` notification
5. 呼叫 `account/rateLimits/read`
6. 從一個或多個 rate-limit buckets 解碼 `usedPercent`、`windowDurationMins` 與 `resetsAt`
7. 健康時保留同一個 app-server connection 供後續刷新重用；timeout、cancellation、EOF、protocol failure 或 App 結束時才完整替換或關閉 child

此 method 與欄位已有 OpenAI 文件，並由 Codex 管理驗證狀態。QuotaPulse 不得讀取 `~/.codex/auth.json` 或複製 token。Adapter 必須清楚呈現找不到執行檔、尚未登入、不提供 ChatGPT 訂閱額度的 API-key-only 模式、protocol 不相容、timeout 與 payload 格式錯誤。

目前實作採單一、按需建立且健康時重用的 app-server。`CodexAppServerClient` actor 合併重疊讀取，connection 只保留一個 stdout reader task 與一筆 response buffer；stderr 直接導向 null device，不建立 reader 或 buffer。每個 request 使用 5 秒 timeout，每行 stdout 上限 1 MiB。timeout、cancellation、EOF、protocol failure、explicit shutdown 或 App termination 都會先關閉 handles、終止並 reap child，再等待 stdout reader 結束；重連完成前不會啟動替代 child。它不讀取 `auth.json`、sessions、logs 或 state databases。

本機以 ChatGPT.app 內建的 `codex-cli 0.149.0-alpha.4.3` 做過 sanitized live probe，確認 method 與欄位型別可用。Production locator 先檢查標準位置及 `NSWorkspace` 發現的 `ChatGPT.app/Contents/Resources/codex`，再回退舊 `Codex.app`、常見獨立 CLI locations 與 GUI process 繼承的受限 `PATH`。ChatGPT.app 與舊 Codex.app 目前共用 `com.openai.codex`，因此 bundle identifier 只用於取得候選位置；locator 還會驗證 bundle 名稱、一般可執行檔與受信任路徑祖先。成功來源只在記憶體快取，每次使用前重新驗證，失效就重新探索。此 runtime path 仍是 app bundle packaging detail，需透過安全 fallback 與跨版本測試持續驗證；使用者 override 尚未實作。

### 可能的備援：本機 Codex session JSONL

Codex session event 可能包含 `primary` 與 `secondary` 視窗的使用百分比、duration 與 reset timestamp，但 persisted schema 是實作細節，最新 session 也可能過期或已封存。掃描 session 還可能接觸含 prompt 與 tool output 的內容。

若未來啟用此備援，必須明確標示 experimental，只讀取候選檔案受限大小的尾端，找到最新 rate-limit event 就停止，立即捨棄無關內容，並把 snapshot 標示為可能過期。目前官方 App Server 已通過本機驗證，因此不實作此備援。

### 拒絕的 Codex 來源

- `auth.json`：憑證儲存，不是用量資料
- screen scraping 互動式 `/status`：脆弱且不是 machine contract
- 由 token 數推估方案額度：provider 可控制加權方式，無法可靠重建

## 7. Claude Code 資料來源評估

### 優先方案：有文件的 status-line JSON 與 opt-in bridge

[Claude Code 官方 status-line 文件](https://code.claude.com/docs/en/statusline) 定義：

- `rate_limits.five_hour.used_percentage`
- `rate_limits.five_hour.resets_at`
- `rate_limits.seven_day.used_percentage`
- `rate_limits.seven_day.resets_at`

Claude Code 會在相關 session event 後啟動已設定的 status-line command，並把小型 JSON 寫入 stdin。QuotaPulse 應使用需要使用者明確同意的 bridge，把最少量 snapshot 以原子方式寫入 `~/Library/Application Support/QuotaPulse/Providers/Claude/`。

只可保留：

- 實際存在的兩個文件化 rate-limit windows
- 可取得時的 Claude Code version
- QuotaPulse bridge schema version
- 本機 capture time

必須捨棄 `cwd`、workspace/repository identity、transcript path、token 數、cost、model、session ID 與所有未知欄位。

限制包括：`rate_limits` 僅為 Claude.ai Pro/Max 訂閱者所文件化；欄位要在 session 第一次 API response 後才出現；任一視窗都可能缺少；更新由事件驅動，Claude Code 閒置時 snapshot 可能過期；安裝 bridge 可能與現有 custom status line 衝突。

Milestone 3 必須設計明確的設定與復原流程。QuotaPulse 不得靜默取代既有 `statusLine.command`。可以產生供現有 script 整合的說明，或在顯示完整設定差異並保留可復原備份後，才安裝 wrapper。

目前已實作的 `ClaudeProvider` 只讀 QuotaPulse-owned、`schemaVersion: 1` 的 `usage-v1.json`。`ClaudeSnapshotReader` 將輸入限制為 16 KiB，拒絕 missing、unreadable、oversized、malformed 與 future-schema files，並保留 `capturedAt` 供後續 stale policy 使用。它不讀取 `~/.claude`、`~/.claude.json`、transcripts、history、stats 或 credentials。完整本機探索與條件式可靠性說明見 `docs/providers/claude-code.md`。

本機 Claude Code package metadata 顯示版本 `1.0.43`，早於官方 changelog 加入 status-line `rate_limits` 的 `2.1.80`；因此沒有宣稱完成本機 live quota 驗證。本機也已有 status-line command，本次沒有讀取其值或修改設定。

### 拒絕的 Claude 來源

- `/usage`：適合互動檢查，但沒有文件說明可作為非互動 machine-readable command
- `~/.claude/projects/**/*.jsonl`：可能很大，且包含敏感對話與 workspace 資料
- `~/.claude/stats-cache.json`：歷史 token 與活動統計，不是訂閱額度
- 未文件化 OAuth usage endpoint 或直接讀取 Keychain token：不穩定且違反不碰憑證的邊界
- 單純為取得額度而發出 Claude request：會消耗額度並傳送資料，不適合被動監看工具

## 8. 刷新與並行模型

`AppModel` 是唯一的 refresh scheduling owner。它在 App 啟動時要求第一次刷新，並且最多只持有一個含 30 秒 tolerance 的 `ContinuousClock` sleeping task；menu view、`RefreshCoordinator`、`UsageService` 與 providers 都不建立週期 timer 或獨立 refresh loop。

v0.1 固定政策：

- 正常完成一輪刷新後，下一輪約在 15 分鐘後執行。
- menu panel 出現時立即使用記憶體中的現有 `ProviderState`／snapshot；任一現有 snapshot 的 `capturedAt` 已超過約 3 分鐘，且距離上一輪讀取完成也至少 3 分鐘時，在背景要求刷新，不等待結果才顯示 UI。後者避免 source 本身過舊時，每次開選單都重新讀取。
- 使用者按下 refresh 或 Command-R 時立即要求刷新；若已有手動或自動刷新進行中，沿用同一輪工作，不啟動重疊工作。
- 刷新開始時保留現有 snapshot 並顯示 refreshing；若同一 provider 最新刷新失敗，`AppModel` 保留上一份有效的記憶體內 snapshot，UI 同時顯示 stale／失敗提示與原始 `capturedAt`。這不建立磁碟 persistence 或 usage history。
- 任一 provider 回傳可重試的 `.failed` 時，共用刷新週期依 1、2、5、15、30 分鐘退避，連續失敗最多 30 分鐘；下一輪沒有 `.failed` 就恢復 15 分鐘。menu open 不會繞過尚未到期的退避；明確手動刷新可以立即重試。`notInstalled`、`notConfigured` 與其他非暫時性 unavailable 狀態不啟動快速重試。此為全 App 共用退避，健康 provider 仍會隨每輪依序更新，不另建 provider timer。
- system sleep 會取消唯一 sleeping task但保留 deadline；wake 時若 deadline 已過就要求一輪刷新，否則只重建一個剩餘時間 schedule。重複 wake 或 App activation 只會確認既有 schedule，不建立第二個 loop。

工作合併分成刻意保留的防線，而不是多套排程：

1. `AppModel` 合併所有 UI、menu、lifecycle 與 scheduled triggers，並發布 loading／完成狀態。
2. `RefreshCoordinator` 只持有一個 in-flight refresh task，讓其他非 UI caller 也不能繞過合併；它不決定時間。
3. `UsageService` actor 依序刷新 providers，逐一轉成獨立 `ProviderState`，單一 provider 失敗不會阻止後續 provider。
4. `CodexAppServerClient` actor 合併同一 provider 的重疊 RPC，健康時重用既有 app-server connection。

普通 refresh 只在健康 connection 上送出新的 `account/rateLimits/read`，不做 executable discovery 或 process recreation。只有 connection 不存在或已失效時才進入 locator／reconnect；重連會先完整停止舊 connection，再探索並建立 replacement。因此 reconnect lifecycle 與正常 refresh cadence 保持分離。

App termination 會取消 App-owned schedule／refresh，並要求 coordinator cancellation；Codex process boundary 仍以自己的同步 termination observer 保證 child cleanup。外部 process 一律維持 timeout、受限 stdout/stderr 與完整 termination cleanup。

畫面倒數使用一分鐘粒度的 `TimelineView(.periodic(from:by:))`，只以 `resetAt - context.date` 計算顯示文字。倒數 tick 不改寫 `AppModel`、不要求新 snapshot，也不會呼叫 provider、locator 或 app-server。不得發布全域一秒 tick，也不持久化持續變動的倒數值。

## 9. 通知

`NotificationService` 擁有 v0.1 的本機通知流程；`ResetNotificationPolicy` 是不依賴 `UserNotifications` 的純決策層，`UserNotificationCenterClient` 才把決策轉成 `UNNotificationRequest`。SwiftUI 不建立 request，也不持有通知去重狀態。Preview 與單元測試注入 fake center／store，不接觸真實通知中心。

### 9.1 評估與 eligibility

`AppModel` 在 `UsageService` 完成本輪 refresh 並發布 UI state、排定既有下一輪 refresh 後，把該輪原始 `ProviderState` 交給 notification service。通知不讀取 UI 為失敗狀態保留的 cached snapshot。每個 window 必須同時符合：

- state 是本輪成功的 `.available`，snapshot 與 state 的 provider identity 相同
- snapshot source 必須是 provider adapter 的真實來源；`.mock` 永遠不具通知資格
- `capturedAt` 距評估時間不超過 15 分鐘；只容許最多 5 分鐘的未來 clock skew
- `resetAt` 是有限值且仍在未來
- provider 不是 `.notInstalled`、`.notConfigured`、`.unsupportedAuthentication`、`.failed` 或 `.stale`

`usedPercentage` 不存在、非有限值或超出 0...100 時，仍可送不含 percentage 的 reset reminder；只有 0...100 的真實 percentage 能產生 remaining quota 文字。

### 9.2 Threshold 與通知種類

v0.1 依 normalized `UsageWindow.duration` 選擇門檻，不做 provider-specific 分支，也不做每 10% 等頻繁 percentage alerts。6 小時以下的短視窗使用 reset 前 1 小時與 30 分鐘；超過 6 小時的長視窗使用 24、6、1 小時候選門檻，並排除長於該視窗本身的門檻。缺少或無效 duration 時不猜測分類，也不建立通知。每個 window／threshold 最多一則：

- remaining percentage 至少 20% 時，送「significant remaining quota」版本，例如 title `Codex resets in 6 hours`，body `You still have 61% of your quota remaining.`
- percentage 缺少、無效或 remaining 低於 20% 時，送不含數字的「reset approaching」版本

20% 是 v0.1 的保守 noise floor，不是方案額度推估，也沒有在本次加入 Settings UI。若 App 第一次看到 window 時已同時跨過多個適用門檻，只送最接近 reset 的一則，並把較早門檻一併標記完成，避免多則提醒同時湧入。

### 9.3 Scheduling strategy

v0.1 選擇 **在既有 refresh 後評估並立即提交一次性 local notification**，不預先建立長期 `UNCalendarNotificationTrigger`。長期 request 若保存目前的 remaining percentage，真正送達時數字可能早已改變；若只保存 reset time，則無法可靠完成「仍有顯著額度」提醒。Refresh-driven delivery 讓 title、body 與 eligibility 都以同一輪新鮮資料決定，也能在 reset timestamp 改變時重新評估，不需維護另一個 scheduler。

正常運作的 menu bar App 最多受既有約 15 分鐘 refresh cadence 影響而延遲；Mac sleep 時不新增喚醒 timer，既有 wake refresh 會補做評估。App 完全退出期間不會產生新提醒，這是 v0.1 為資料正確性與低資源使用接受的限制。提交給通知中心的 1 秒 non-repeating trigger 只用於讓系統顯示已決定的即時通知，不是 refresh scheduler 或長時間 Task。

### 9.4 去重、reset window identity 與 timestamp 變更

去重 identity 由 provider、穩定的 usage-window ID、logical reset-window identity 與 threshold 組成。Reset timestamp 以分鐘正規化，兩分鐘內的解析／clock 差異視為同一值。每個 provider/window 只保留目前 logical window：

- 舊 reset 尚未到期時，不論 timestamp 往前或往後移，仍視為同一 logical window；更新目前 reset time，但保留已送 thresholds
- reset 移早且已經過期時不送；下一個未來 reset 出現後建立新 logical window
- 舊 reset 已經過期後出現新的未來 reset，視為真正的新 window，該 duration class 的門檻重新 eligible
- 若 provider 在舊 reset 已過後才宣告它其實往後移，無法與新 window 完全可靠區分；v0.1 保守地視為新 window，這是剩餘 edge case

`UserDefaultsNotificationStateStore` 只保存 schema version、provider、window ID、分鐘化 reset identity／目前 reset、已完成 thresholds 與最後觀察分鐘，不保存通知文案、percentage、snapshot、provider payload 或憑證。既有以小時保存的 threshold metadata 會相容轉成分鐘，保留跨版本去重；舊格式 pending request 則會在首次通知評估時移除。相同 provider/window 的新 generation 會取代舊 generation，全域另設 32 entries 上限，encoded state 超過 64 KiB 時拒絕讀取，沒有無限成長的 history。

Service 在提交 request 前先持久化 threshold claim，以 App restart 與重複 refresh 的「最多一次」語意優先；若系統在 claim 後拒絕 `add`，該單一 threshold 可能漏送，但不會重送。Process 內以 evaluation generation 與提交前重新讀取 state 防止兩次 async evaluation 在 authorization suspension point 重複提交。

### 9.5 Stale data 與權限

本輪 refresh 失敗、typed unavailable 或 snapshot 超過 15 分鐘時，不建立新通知、不改寫已完成 thresholds，也不移除其他有效 request；因 v0.1 沒有長期 future reset requests，stale refresh 通常沒有待取消項目。各 provider 分開評估與去重，一個 provider 狀態不影響另一個。

只有出現第一個 eligible decision 且 authorization status 是 `.notDetermined` 時才要求 `.alert`／`.sound` 權限。並行評估共用同一個 authorization request；權限等待結束後，service 只讓最新一輪評估繼續，並以等待後的時間重新檢查 freshness、reset 與 dedup state。這避免使用者停留在系統提示期間又完成更新時，舊 percentage 或已過期 reset 才被送出。

之後先讀 system settings；`.denied` 不再要求、不送通知，也不影響 provider refresh、UI 或下一輪排程。使用者日後在 System Settings 重新允許後，尚未 claim 且仍 eligible 的 threshold 可在下一輪 refresh 送出。`UserNotificationCenterClient` 持有 notification center delegate，讓 App 在前景時也能要求 banner／sound presentation。Debug build 的 Settings 提供 development-only action，透過同一個 `UserNotificationCenterClient` 要求授權並排定約五秒後的固定 identifier 測試通知；其 protocol method、model action、feedback state 與 UI 全部以 `#if DEBUG` 排除於 Release。授權與本機通知提交遵循 Apple 的 [Requesting authorization](https://developer.apple.com/documentation/usernotifications/asking-permission-to-use-notifications) 與 [Scheduling a notification locally](https://developer.apple.com/documentation/usernotifications/scheduling-a-notification-locally-from-your-app) 流程。

## 10. 設定

v0.1 使用原生 `Settings` scene 與 `@MainActor SettingsStore`。`SettingsStore` 是 provider enablement、通知總開關，以及短視窗 1 小時／30 分鐘與長視窗 24／6／1 小時門檻的單一來源，並以 typed UserDefaults keys 保存；SwiftUI 只透過 `SettingsModel` 修改 store，再由 `UsageService` 與 `NotificationService` 讀取同一份狀態。短、長視窗的 1 小時選項彼此獨立，舊版共用 1 小時偏好會作為短視窗偏好的 migration 預設。`NotificationService` 關閉時不再建立提醒，並移除 QuotaPulse 自己的 pending reset requests；關閉單一門檻只移除相符 duration class 的門檻。

Launch at Login 使用 `ServiceManagement` 的 `SMAppService.mainApp`。Settings 每次顯示時重新讀取 system status；register／unregister 失敗時保留系統實際狀態並顯示安全錯誤，不把 UI toggle 當成成功依據。

Provider 停用後，`UsageService` 仍保留 provider 順序與 normalized `.disabled` state，但跳過其 `fetchUsage()`；其他 providers 繼續依序刷新。重新啟用會要求一次共用 refresh，仍經 `RefreshCoordinator` 合併。健康 Codex app-server connection 不因設定開關反覆銷毀與重建。

背景刷新維持固定約 15 分鐘。動態 interval 會介入已完成的 deadline、retry backoff、sleep/wake 與單一 scheduled task invariant；v0.1 不為 5／15／30 分鐘選項擴大該架構。Settings 只顯示目前固定 cadence。

Claude Code 在 Settings 明確標為 Experimental／Unverified，只有 enable／disable，沒有 bridge 安裝或設定。不得使用 iCloud key-value storage，也不得保存 provider 憑證。

## 11. 未來 Reset Intelligence 邊界

Reset Intelligence 是獨立資料產品，不是 `UsageProvider` 的另一個 method。

```swift
struct ResetEvent: Identifiable, Sendable {
    let id: String
    let providerID: ProviderID
    let announcedResetAt: Date?
    let publishedAt: Date?
    let publisher: String
    let originalSourceURL: URL
    let retrievedAt: Date
    let scope: ResetScope
    let trust: ResetTrust
}
```

`ResetEventService` 未來可使用 `URLSession`，但 cache、network client、models 與 settings 都必須與本機 usage adapters 分開。每個事件都必須保留可點擊的原始來源 URL 與 publisher；推導出的信心、摘要與去重 metadata 只能補充，不能取代來源。遠端 request 不得含本機用量 snapshot、prompt、repository 資訊或程式開發歷史。

## 12. Milestone 1 檔案結構

```text
QuotaPulse.xcodeproj/
QuotaPulse/
├── App/
│   ├── QuotaPulseApp.swift
│   ├── AppModel.swift
│   └── AppDependencies.swift
├── Domain/
│   ├── ProviderID.swift
│   ├── ProviderStatus.swift
│   ├── ProviderUsageSnapshot.swift
│   ├── ResetCountdown.swift
│   ├── UsageSource.swift
│   └── UsageWindow.swift
├── Providers/
│   ├── UsageProvider.swift
│   ├── Mock/
│   │   └── MockUsageProvider.swift
│   ├── Codex/
│       ├── CodexProvider.swift
│       ├── CodexAppServerClient.swift
│       ├── CodexExecutableLocator.swift
│       └── CodexDTO.swift
│   └── Claude/
│       ├── ClaudeProvider.swift
│       ├── ClaudeSnapshotDTO.swift
│       └── ClaudeSnapshotReader.swift
├── Services/
│   ├── UsageService.swift
│   ├── RefreshCoordinator.swift
│   ├── ResetNotificationPolicy.swift
│   ├── NotificationService.swift
│   ├── SettingsStore.swift
│   └── LaunchAtLoginController.swift
└── Features/
    ├── MenuBar/
    │   ├── DashboardView.swift
    │   ├── ProviderCardView.swift
    │   ├── UsageWindowRow.swift
    │   └── ProviderStateView.swift
    └── Settings/
        ├── SettingsModel.swift
        └── SettingsView.swift
QuotaPulseTests/
├── App/
├── Domain/
├── Providers/
└── Services/
```

Codex 與 Claude provider cores 已透過共用應用程式架構接入，且 Codex 已完成本機 live runtime 與 release lifecycle validation。Codex 已將 executable 缺少映射為 `notInstalled`、launch failure 映射為 `runtimeLaunchFailed`、無可用 window 映射為 `usageUnavailable`，其餘 app-server failure 映射為 `refreshFailed`；這些狀態都不含原始 provider payload。因官方尚未定義各 authentication failure 的穩定 error shape，目前不猜測 `unsupportedAuthentication`。Claude snapshot 缺少映射為 `notConfigured`，UI 固定標示為 `Experimental`／`Unverified`，直到完成 bridge 與正式訂閱帳號驗證。Milestone 3 尚須完成明確 opt-in 的 status-line bridge、既有 command 保留／復原與 live fixture validation。不要為了對齊架構圖，預先加入空的未來 service 或 provider。

## 13. 測試與驗證

Milestone 1 自動測試涵蓋：

- 百分比正規化與剩餘百分比
- 過期、缺少、分鐘、時數與天數倒數格式
- 重複刷新合併
- 啟動與 15 分鐘 scheduled refresh、3 分鐘 menu stale threshold、手動／自動重疊合併
- 1／2／5／15／30 分鐘 failure backoff 與成功後恢復正常週期
- 反覆 menu open、sleep／wake 與 App activation 不累積 refresh schedules
- 倒數時間推進不讀取 provider
- 以注入 service 驗證通知 action
- Codex single/multi-bucket mapping、缺少 window 與不猜測 percentage
- Codex availability、last-updated、reset timestamp、sanitized provider failure 與 missing executable 狀態
- app-server 正常、健康 connection 重用、重疊讀取合併、失敗重連、child reap、handle cleanup、缺欄位與 malformed response、stdout 上限、timeout 與 process termination
- Claude five-hour/seven-day mapping、independently missing window 與不猜測 percentage/reset time
- Claude snapshot missing、malformed/partial、oversized、future-schema 與 stale capture metadata
- 多 provider 順序、逐一失敗隔離、兩者同時 unavailable、每次刷新重新 fetch 與 provider/snapshot identity 一致性
- `AppModel` loading transition，以及全數 unavailable 時不虛構成功更新時間
- provider presentation 的 available／loading／unavailable／not detected／not configured／refresh failure／cached failure／missing reset／stale／Claude experimental 狀態，以及 user-facing 文案不洩漏內部錯誤
- 最新刷新失敗時保留上一份有效的記憶體內 snapshot 與成功更新時間

後續 provider 工作還需要測試 app-server request/response correlation、正式 Claude status-line fixtures、bridge atomic write 與 permissions、existing-command composition、settings migration，以及各支援版本與 authentication modes 的 live behavior。

v0.1 發行前仍須手動驗證：Release build 啟動、選單開關、Settings 與 quit、VoiceOver 與鍵盤、亮暗模式、窄版配置、工具缺少/登出/斷線/過期狀態、console error、長時間記憶體與 CPU、retain cycle、timer、process、file handle 與 async task。

編譯與 fixture 測試不能證明即時 Codex/Claude 整合、系統通知實際送達、notarization、記憶體目標或外部散布。回報時必須分開列出各種驗證。

## 14. 待決事項與不確定性

1. 確認是否長期維持 macOS 14 為最低支援版本。
2. 確認直接 notarized distribution，以及是否有意不啟用 App Sandbox。
3. 決定是否仍需要 GUI executable override；目前已支援 ChatGPT.app 整合 runtime、舊 Codex.app、常見 CLI locations 與 GUI process 繼承的 `PATH`，但不載入 interactive shell 設定。
4. 實測支援的 Codex versions 與 authentication modes 對 app-server 的相容性。
5. 決定 QuotaPulse 是否修改 Claude settings，或只產生 opt-in bridge 說明。
6. 定義現有 Claude status-line command 的保留與復原方式。
7. 依實際使用回饋確認目前 15 分鐘 presentation freshness label 門檻是否需要調整。
8. 依 `docs/PERFORMANCE.md` 量測長駐健康 app-server、重複刷新與重連是否符合延遲、記憶體、CPU、file descriptor 與 task 目標。
9. 承諾散布方式前，驗證 signing、hardened runtime 與 child-process 行為。

這些都是明確的後續里程碑，不得藏在 provider implementation 裡當成已成立的假設。
