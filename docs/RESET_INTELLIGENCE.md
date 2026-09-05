# Reset Intelligence

## 狀態與範圍

QuotaMew 已實作 provider-agnostic 的**本機 quota reset detection**。官方外部 Reset Intelligence feed 的擷取、polling、cache 與呈現仍為 **FUTURE**。

這兩個責任不共用資料擷取路徑：

1. `LocalResetDetector` 在既有 provider usage refresh 後，從 normalized `ProviderState` 判斷 quota window 是否進入新 cycle。
2. 未來 `ResetEventSource` 可從經審查的小型 feed 取得官方全域、額外或已完成 reset 事件。它不屬於 `UsageProvider`，也不得與 provider refresh scheduler 綁在一起。

本階段沒有 X/Twitter 爬蟲、AI 分類、backend、GitHub Actions feed collection、新 provider、usage history 或 iPhone 支援。

## 本機 reset detection

Detector 只評估以下 snapshot：

- provider state 為 `.available`，且 snapshot/provider identity 一致
- source 是真實 provider adapter，不是 `.mock`
- `capturedAt` 距評估時間不超過 15 分鐘，最多容忍 5 分鐘未來 clock skew
- `UsageWindow.id` 有效且 `resetAt` 是有限時間
- 觀測比同 provider/window 的 persisted baseline 更新

第一次觀測只建立 baseline，不推測 App 不在執行時曾發生的 reset。後續觀測依下列證據判斷：

- provider 明確提供的 cycle identifier 已改變；或
- 舊 `resetAt` boundary 已到，新 `resetAt` 往後進入新視窗；或
- usage 至少降低 25 percentage points，同時 `resetAt` 往後移動足以代表新視窗。有 `duration` 時至少移動一半 duration，否則至少 30 分鐘。

Percentage 下降本身永遠不足以代表 reset。這可排除使用量修正、provider 重算與短暫 malformed response。

### 保守失敗處理

- `resetAt` 暫時缺少時忽略該次 window，但不破壞上次 baseline。
- stale、out-of-order、mock 與 typed unavailable states 不產生 reset。
- `resetAt` 在 2 分鐘內的變動是 timestamp correction，不是新 cycle。
- 同一 provider/window 觀測間隔超過 2 小時時，只以新資料重建 baseline。這避免 provider reconnect、長時間 sleep 或 App 未執行期間的未知變化被猜成 reset。
- 證據不足時不送，不補造 reset time、usage 或 cycle identity。

## Reset window identity

Provider/window baseline 的 key 是：

```text
providerID + UsageWindow.id
```

特定 reset cycle 的 identity 是：

```text
providerID + UsageWindow.id + cycleIdentifier
```

`cycleIdentifier` 優先使用 normalized `UsageWindow.resetCycleIdentifier`。Provider 未提供時，改用分鐘化 `resetAt`。`UsageWindow.id` 是「5-hour」或「weekly」這類穩定 logical window ID，不應每個 cycle 都改變。

## Persistence 與通知去重

`UserDefaultsNotificationStateStore` 以獨立 versioned payload 保存本機 detector baseline。每個 entry 只含：

- provider 與 window ID
- 目前 cycle identity 與 optional provider cycle identity
- 分鐘化 reset time
- 秒級 captured time
- 上次有效 usage percentage
- 最後已通知 cycle identity

最多保留 32 個 provider/window entries，identifier 最多 256 bytes，encoded payload 上限 64 KiB。舊 entry 被新 baseline 取代，不建立 reset history。

Detector 在通知授權與 request submission 前持久化 notification claim。語意是 **at most once**：若保存後系統拒絕 request，該通知可能漏送；但同一 provider/window/cycle 不會因重複 refresh 或 App restart 再送。

## 本機 reset notification

Completed reset 使用現有 `NotificationService` 與 permission handling。Title 來自 normalized provider display name，body 來自 normalized window label/duration，不寫死 Codex 分支，並提供 English 與繁體中文在地化。

Completed-reset 通知共用現有 notifications 總開關與 provider enablement。目前不增加 Settings UI；關閉特定 1-hour/30-minute/long-window reminder threshold 不會關閉 completed reset。即使 notifications 總開關關閉，detector 仍更新 baseline，避免日後重開時回頭通知舊 reset。原有短視窗、長視窗提醒與 threshold dedup schema 保持不變。

## ResetEvent domain

`ResetEvent` 是 provider-independent、`Codable` 且 `Sendable` 的外部 event value type。v0.2 Milestone A 加入 stable `id`、monotonic `revision`、`publisher`、`retrievedAt`、`effectiveUntil`、verification，以及 correction/retraction relationship；typed kinds 包含 global announce/completed、banked reset、temporary increase、expected range、correction 和 retraction。完整 schema、bounds、forward-compatibility 及 editorial policy 以 [RESET_INTELLIGENCE_FEED.md](RESET_INTELLIGENCE_FEED.md) 為唯一契約來源。

本機 `DetectedQuotaReset` 與官方 `ResetEvent` 刻意分開。前者是本機觀測，沒有外部原始公告；後者必須保留 publisher 與可點擊 source URL。不應為了共用型別而虛構來源。

## Future ResetEvent feed

本階段只保留最小 abstraction：

```swift
protocol ResetEventSource: Sendable {
    func fetchEvents() async throws -> [ResetEvent]
}
```

Milestone A 已定義 JSON schema、hard bounds、event dedup、更正／撤回語意與 Settings opt-in contract；future production source 的 cache、ETag、reader、polling cadence 與 notification settings 仍未實作。它不呼叫 `UsageProvider`、不產生額外 Codex app-server process，也不與目前約 15 分鐘 provider refresh loop 耦合。

## Trusted-source policy

可接受的未來來源可包含官方 OpenAI 公告、明確可驗證的 OpenAI/Codex 團隊公告，以及 provider-owned status/help pages。每個 event 必須保留原始 `sourceName` 與可點擊 `sourceURL`。

QuotaMew 不得將 AI 產生的解釋呈現為權威來源。`displaySummary` 只是顯示安全的補充文字，不取代原文。App 不需要 social-media credentials，也不直接爬取 X/Twitter。

## 隱私與資源限制

- 所有 local detection 都在 Mac 上完成，不上傳 usage snapshot、percentage、reset time 或 workspace metadata。
- 未來 feed request 不得附帶 usage、prompt、repository、transcript、local path 或 coding history。
- 不建立高頻 polling、second-level timer、無上限 event history、新 provider scheduler 或額外 Codex process。
- 現有 refresh 仍由 `AppModel` 的單一 coalesced schedule 驅動；reset detection 只是 refresh completion 後的小型純計算。

## 仍不明確的 provider 行為

- 現有 Codex 與 Claude normalized data 未提供 explicit reset-cycle ID，因此目前使用分鐘化 `resetAt` fallback。
- Provider 可在舊 boundary 前後大幅改動 `resetAt`。若沒有 explicit cycle ID、舊 boundary 未到且 usage 也沒有大幅下降，detector 保守地不發通知。
- App 結束、Mac 長時間 sleep 或 provider 長時間 unavailable 期間可能真正發生 reset。為了避免 false positive，重連後只重建 baseline，不回溯通知。
