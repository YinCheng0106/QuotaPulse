# Reset Intelligence Feed Contract

狀態：**v0.2 Milestone A frozen contract**（2026-08-31）。本文件定義未來由 QuotaMew 讀取的公開、靜態 JSON feed；本里程碑沒有 reader、cache、ETag、URLSession、排程或 UI。

## 邊界與資料流

外部 feed 事件不是本機偵測到的 reset。`DetectedQuotaReset` 是使用者 Mac 上的 fresh normalized provider state 所形成的本機證據；`ResetEvent` 是可信發布者公開發布、可追溯到來源 URL 的 metadata。兩者日後可以只在本機配對，但不可合併為同一種 truth source。

未來唯一允許的資料流為：

```text
static trusted feed -> ResetEventSource -> ResetEventService (future)
                    -> bounded ResetEventFeed -> future presentation/matching
```

它獨立於 `UsageProvider`、`UsageService`、`RefreshCoordinator`、Codex app-server 與 Claude snapshot reader。任何 feed failure 都不能延遲、取消或改變本機 quota refresh。

## Schema v1

檔案是完整快照，不依賴 array order：

```json
{
  "schemaVersion": 1,
  "generatedAt": "2026-01-10T12:00:00Z",
  "events": []
}
```

所有時間是 RFC 3339 / ISO 8601 absolute timestamp。`generatedAt` 是維護者生成此完整快照的時間，不是事件生效時間。每筆 event 有 `id`、正整數 `revision`、`providerID`、`kind`、`publisher`、`sourceURL`、`publishedAt`、`retrievedAt`、optional `effectiveAt` / `effectiveUntil` / `expiresAt`、`audience`、`verification`、display-safe `displaySummary`、optional locale identifier，以及 correction/retraction relationship。

`effectiveAt` 是已知的精確起點；只有來源明確給範圍時才同時提供 `effectiveAt` 和 `effectiveUntil`。未知時間兩者皆省略，不能以「tomorrow」這類相對文字取代 machine-readable time。`expiresAt` 是事件本身不再適合主動呈現的時間，非 quota window 的 reset time。`publishedAt` 來自來源；`retrievedAt` 是 maintainer 取得/復核來源的時間，且不得早於 `publishedAt`。

## Stable ID、revision 與關係

`id` 是 lowercase ASCII stable logical-event ID（`a-z`、`0-9`、`.`、`_`、`-`，最多 128 UTF-8 bytes），不是 source URL。相同 logical event 的 source URL、時間或摘要修正時，ID 不變而 `revision` 以正整數單調增加。完整 feed 每個 ID 只出現一次，且表示目前 authoritative revision；較新 revision 取代同 ID 的舊表示。reader 對 last-known-good snapshot 驗證時，較低 revision 或同 revision 但內容不同都必須拒絕。

`kind` 的 typed cases 是：`globalResetAnnounced`、`globalResetCompleted`、`bankedResetGranted`、`temporaryQuotaIncrease`、`resetExpected`、`correction`、`retraction`。未知 kind 在 decoding 時會被明確辨識為 unknown，且 v1 feed 整體拒絕；不以 untyped string 當作可呈現事件。

一般 revision 是同一 ID 的修訂。跨 ID 的 editorial notice 使用關係欄位：

- `correction` 必須有 `correctsEventID`；它會取代被指向的原始 event 的 active presentation。
- `retraction` 必須有 `retractsEventID`；它會使被指向的原始 event 及其 correction notices 不再進入未來的 active presentation。
- 兩者只能指向同 provider、同一份 feed 中的普通原始 event；target 不能自己帶 correction/retraction relationship。這是單層關係，避免循環與無限鏈。

已送出的通知歷史不在本里程碑處理。後續通知 layer 必須以 `(event ID, revision)` 去重，並能對 correction/retraction 做明確的 history policy，不能悄悄重送或宣稱使用者已獲得資格。

## Audience 與 verification

`audience` 是物件：`allUsers`、`paidUsers`、`planFamilies`（最多 8 個明確、文件化 family 名稱），或 `unspecified`。它描述公告的公開條件，從不由 local quota data 推論帳號 entitlement。舉例說，banked reset 可說「eligible users may have…」，不能說「你已取得」。

`verification` 僅有 `official`、`trustedPublisher`、`unverified`，沒有信心分數。Phase 1 正常只發布前兩者；權威證據永遠是 `publisher` 加 `sourceURL`，AI 摘要不可成為權威。

## Atomic validation 與硬上限

Feed 是不可信輸入。任何 schema 或內部一致性錯誤都拒絕**整份**候選 snapshot，保留 future reader 的 last-known-good cache；絕不讓壞 feed 影響 local provider quota operation。v1 不採 per-event partial acceptance，因為漏掉 relation 或 revision 仍可能導致錯誤呈現。

| 項目 | v1 上限 |
| --- | ---: |
| response body | 256 KiB |
| events | 128 |
| ID | 128 bytes |
| revision | 1…1,000,000,000 |
| publisher | 120 bytes |
| display summary | 500 bytes |
| URL | 2,048 bytes，HTTPS 且有 host |
| locale ID | 35 bytes |
| plan families | 8 × 64 bytes |

不支援的 future schema、unknown provider、unknown kind、malformed timestamp、非 HTTPS / invalid URL、duplicate ID、revision regression、衝突的同 revision、空或 oversized field、超量 events、無效 audience，以及無效 correction/retraction target 都安全失敗。這些 limits 同時防止無上限 remote array/string 進入記憶體。

## Editorial governance

可接受來源只有：官方 provider documentation、官方 provider status/help pages，以及可歸屬的 provider employee/team account。每筆接受事件都必須有原始 source URL、publisher、可得時的 publication timestamp 與 maintainer review。維護者應保留足夠 review context 以判斷來源、時間、audience、revision 和 correction/retraction 是否正確。

AI 可以協助維護者尋找或摘要候選；AI 不得自行發布 event、標記 verification、替換 source、發明 effective time，或判定使用者 eligibility。static feed 是公開資料，不含 QuotaMew usage、帳號、裝置、workspace、prompt、repository path、transcript 或 token。未來 feed request 也不得夾帶那些資料。

更正以同 ID 較高 revision 或經 review 的 `correction` 發布；撤回必須保留自己的 publisher/sourceURL 與 `retraction` 關係。維護者不可刪除已發布事件來隱藏修正；後續 active-presentation policy 才依這些關係決定顯示。

## Settings / onboarding contracts reserved for later milestones

Settings IA 固定為 **General**、**Providers**、**Notifications**，不建立 Advanced。General 將擁有 Launch at Login、Show in Menu Bar、Used/Remaining、pinned provider、replay onboarding、Diagnostics，以及 Reset Intelligence opt-in；Providers 只擁有 Codex / Claude enablement 和 status；Notifications 保有既有 thresholds、completed reset 與未來 external-event notification controls。控制項不跨頁重複。

`presentation.usage.mode` 是 `remaining` / `used` 的 presentation-only enum，default `remaining`，不得改 `UsageWindow`、detector、notification threshold 或 provider DTO。`presentation.menu-bar.pinned-provider` 是 optional raw `ProviderID`；nil 代表未 pin。停用或暫時 unavailable 不得改寫 pin；未知 raw value（例如舊版降級）不能渲染、也不能被擦除；唯一 enabled provider 也不會自動建立 pin。

`onboarding.state` 是 `neverShown` / `completed` / `skipped`，另以 `onboarding.last-completed-version` 記錄完成或略過時的 contract version。fresh install 是 `neverShown` / `0`。replay 是 session-only request，不持久化、不得重置任何 provider 或 presentation preference。未來 app update 不會自動重開 onboarding；只有明確 migration 才能改寫 state。`reset-intelligence.enabled` default `false`，保留使用者明確 opt-in 才允許未來網路 reader 啟動；本 Milestone 不保存 cache metadata。
