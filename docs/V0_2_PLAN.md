# QuotaPulse v0.2 產品範圍

> 決策日期：2026-08-31
> 性質：規劃與狀態文件。此文件不代表任何 v0.2 功能已簽署、已公證或已發行。

## 決策摘要

v0.2 的最小高價值目標是讓 QuotaPulse 成為 **reset-aware AI coding quota assistant**：在不蒐集開發工作內容、不增加高頻輪詢的前提下，讓重度 Codex 使用者一眼看到自己選擇的額度呈現，並在有可追溯官方事件時，知道它與自己的本機快照有何關聯。

次要差異點只有兩項：

1. **隱私優先的本機額度視圖**：provider authentication、usage snapshot 與配對判斷留在 Mac 上。
2. **可追溯的 reset 資訊**：每一筆官方事件都連回原始來源；AI 摘要永遠不是權威來源。

這不是 generic AI dashboard、使用分析或 provider 數量競賽。v0.2 不以 binary distribution、Sparkle、歷史圖表或未驗證的 Claude 支援為交付目標。

## Milestone 狀態

| Milestone | 狀態 |
| --- | --- |
| A — contract freeze | **COMPLETE / frozen**；trusted feed、presentation preference、pinned-provider 與 onboarding persistence contracts 已由 fixtures 與 deterministic tests 鎖定。 |
| B — Display + Settings | **Implementation complete through the current SwiftUI shell**；final acceptance 仍待 Hybrid NSStatusItem migration、XCTest zero-status-item-host gate 與 final runtime/manual validation。 |
| C — Onboarding | **NOT STARTED**；目前 scope 暫停，不能由本 checkpoint 偷渡開始。 |

## 已交付的 v0.1.1 基準

| 項目 | 判定 | v0.2 的處理方式 |
| --- | --- | --- |
| Codex provider | 已完成；ChatGPT.app bundled runtime 曾完成 live validation | 保留 app-server-first 與安全失敗；持續收集相容性證據，不重做 provider。 |
| Claude experimental foundation | 部分完成 | bounded snapshot reader 與共用 UI 已存在；bridge、setup/restore、實際訂閱帳號驗證仍缺。 |
| Provider enable/disable | 已完成 | disabled provider 不 fetch、不通知、不出現在 Dashboard；重啟用與 in-flight refresh race 已有保護。 |
| Refresh lifecycle | 已完成 | `AppModel` 保有單一 provider refresh lifecycle；不得為 v0.2 另建 provider polling loop。 |
| Reset reminders 與 completed-reset notification | 已完成 | 已有本機 detector、重啟去重與通知交付路徑；只維護 regression 與 opt-in 系統送達證據。 |
| Local reset detection | 已完成 | 僅接受新鮮 `.available` 非 mock snapshot、強 cycle evidence；百分比下降本身不算 reset。 |
| MenuBar recovery | Milestone B P0 修正已實作，B 仍未完成 | OFF 改為隱藏 status item 並保持目前 process；explicit reopen 提供 recovery，hidden login-item launch 安靜退出。保留 persisted intent、runtime insertion 與 system visibility 三者區分；不以重插入 loop、private Control Center state 或 bundle ID workaround 處理。 |
| Debug/Release identity isolation | 已完成 | 不更改 bundle identifier；每次 artifact 驗證另行確認實際 build identity。 |
| Production App Icon 與英／繁中本地化 | 已完成 | 只隨新增 UI 補齊字串與可近用性，不重開 branding 專案。 |
| Privacy-safe Diagnostics | 已完成 | 已有 allowlisted Copy Diagnostics；每個新 network/provider state 必須擴充 allowlist 與 regression test。 |
| `ResetEvent` / `ResetEventSource` boundary | 已完成，但外部 feed 未實作 | 作為 v0.2 feed 的起點；需補 verification、retrieval、revision、correction/retraction schema。 |

已知系統層級驗證（Notification Center 實際送達、Control Center 可見性、Launch at Login）仍應與自動化測試分列，不把先前的單機結果當成所有使用者的保證。

## 候選項目判斷

| 候選／分類 | 價值、對象與差異 | 複雜度／維護 | 隱私、資源與可靠性／依賴 |
| --- | --- | --- | --- |
| 1. Completed-reset notification — **已完成** | 對受 rolling window 限制者價值高；已是可信差異點。 | 不應重做；只維護 regression。 | 無新增網路/資源；維持 at-most-once、restart-safe 去重與 false-positive 保護。 |
| 2. Official Reset Intelligence — **MUST** | 重度 Codex 使用者的高差異化資訊，非 generic dashboard。 | L／中等 editorial 維護；只做人工審核 static feed ingestion。 | 可選低頻 GitHub fetch；依賴可追溯來源、schema 與 review，不做 collector/backend。 |
| 3. 官方事件 + 本機 quota 結合 — **SHOULD** | 讓事件可行動，尤其仍有大量剩餘額度者。 | M／低至中等；併入 feed 工作流。 | 僅 fresh snapshot + verified/audience-matched event；不能承諾 bonus eligibility，無 usage upload。 |
| 4. Menu bar provider selection — **SHOULD** | 每日 glanceability；對單一主力 provider 使用者最有感。 | M／低維護；只做一個 pinned provider。 | 純本機、無 CPU/network；不可自動切換、輪播或多 provider title，以免狀態不可靠。 |
| 5. Remaining vs Used — **SHOULD** | 同上，減少認知轉換；不以功能數量取勝。 | S／低維護；presentation-only formatter。 | 無資料新增；不得改變 domain calculation、進度、detector 或 notifications。 |
| 6. Menu bar secondary action — **DEFER** | 便利性有限，現有 window footer 已涵蓋核心動作。 | L／高回歸維護；需 AppKit shell spike。 | `MenuBarExtra(.window)` 無獨立 secondary-click API；依賴 `NSStatusItem` 行為、鍵盤與多螢幕驗證。 |
| 7. Settings information architecture — **SHOULD** | 防止 v0.2 設定變成難讀表單。 | M／低維護；General／Providers／Notifications。 | 純 UI；依賴 Display/feed preference，不建空泛 Advanced tab。 |
| 8. Onboarding — **MUST** | 降低 source-build 新手與隱私敏感者的設定疑慮。 | M／低維護；單頁、可略過/重看。 | 無 telemetry/network；依賴既有 diagnostics model，系統通知只能明確動作後請求。 |
| 9. Diagnostics — **已完成** | 高維護價值，但不是新 scope。 | 只隨新 state 補 allowlist/test。 | 無 raw payload/path；維持 copy output 的 privacy safety。 |
| 10. Update checking — **DEFER** | 對 source-only 使用者價值低。 | S/M，但會增加後續 network/support 面。 | 依賴第一個 signed/notarized binary；否則不查 GitHub Releases API。 |
| 11. Automatic update — **DEFER** | 未達 binary 散布前沒有用戶價值。 | L／持續安全維護；未來用 Sparkle 2。 | 依賴 Developer ID、notarization、artifact、appcast、EdDSA 與多次穩定 release；拒絕 custom updater。 |
| 12. Claude Code full support — **DEFER（驗證 gate）** | 多 agent 使用者有價值，但承諾過早會損害可信度。 | L／高維護；bridge/setup/restore。 | 依賴合格訂閱帳號、support-version fixtures 與 clean/existing config 驗證；維持 Experimental / Unverified。 |
| 13. Gemini CLI — **DEFER** | provider breadth 的邊際價值低於可靠合約。 | L／高相容性維護。 | `/stats model` 是互動表面，非安全 pull contract；不 screen-scrape/啟動 session。 |
| 13. OpenCode — **REJECT（本版）** | 有方案 quota，但與產品主力使用者及 contract 不匹配。 | L／高維護。 | 未見文件化 current-usage read contract；本機 server 也有 project/path/config 面，不能作 provider 基礎。 |
| 14. Usage pacing / burn rate — **DEFER** | 潛在價值高，但差異化不足以抵銷誤報。 | L／高維護；先離線 fixtures。 | 依賴同 cycle 足量 fresh samples；跨裝置/sleep/reset 下只能輸出 insufficient data，否則不做。 |
| 15. Local history — **DEFER** | chart 尚未證明會改善日常決策。 | L／storage migration/retention/UI 維護。 | 會增加本機敏感 usage footprint 與 disk/CPU；不先導入 SwiftData/SQLite。 |
| 16. Distribution — **DEFER（獨立軌）** | 採用價值很高，但非 v0.2 feature blocker。 | XL／release 維護。 | 依賴 Apple Developer Program、sign/notarize 與 installed-app proof；不以 unsigned workaround 取代。 |

### Reset Intelligence 架構決策

採用 **A + B 的最小組合**：維護者人工審核的、版本化 static JSON，託管於公開 GitHub repository；App 只讀該 feed。GitHub Actions 僅驗證 schema、URL、時間、stable ID/revision 與 correction/retraction 關係，不能蒐集來源或自動發布事件。

不採用：

- GitHub Actions collector、Cloudflare Worker、輕量 backend：都會引入來源爬取、uptime、濫用、成本與 editorial 責任。
- App 直接輪詢 X、公告頁或 help page：來源格式不穩定，會把網路、隱私與維護風險放進每台 Mac。
- hybrid rules + AI classifier 自動發布：AI 只能協助維護者整理候選，永遠不能成為 event publisher 或 authority。

feed 的每筆事件至少有：schema version、stable ID、revision、provider、event kind、publisher、原始 source URL、publication time、retrieval time、effective time/range、audience、verification status、display-safe summary，以及 correction/retraction relationship。這補齊目前 `ResetEvent` abstraction 尚未模型化的治理資料。

App 端必須有大小上限、ETag、expiry、last-known-good cache、離線安全失敗、event/revision 去重與手動 refresh。自動抓取只在啟動及低頻（最長 12 小時一次）執行，且由獨立、coalesced 的 `ResetEventService` 擁有；絕不綁到 15 分鐘 provider refresh，也不傳送 usage、reset、workspace、裝置 ID 或 prompt。使用者應能在 Settings 關閉這個可選網路功能。

## v0.2 範圍：三個工作流

### A. 每日額度呈現與可擴充 Settings — M

**問題**：選單列目前只顯示固定 icon；Dashboard 雖同時顯示 used/remaining，使用者無法選擇自己每日最需要的主資訊。單一 Settings Form 也即將因 Display 與 feed option 變得難讀。

**使用者收益**：重度 Codex／多 agent 開發者能在不開啟 dashboard 的情況下，穩定看到自己指定 provider 的一個一致數字；不需要猜測 App 為何切換。

**實作輪廓**：新增 presentation-only preference（`used` 或 `remaining`）與固定 pinned provider；選單列為 icon-only 或 provider short label + 一個整數 percentage。Dashboard 對 primary metric 與 VoiceOver value 套用同一 preference，進度色與 notification/detector 計算不變。Settings 只拆 General／Providers／Notifications；Display 放 General，Diagnostics 仍為 General 入口。

**依賴／架構**：新增 display preference store 與 presentation formatter，不修改 `UsageWindow` 的 quota calculation、`UsageService`、`RefreshCoordinator` 或 `NotificationService`。

**維護／隱私**：低；純本機 preference，無新資料與網路。

**驗收條件**：pinned provider 不可用時維持該選擇並顯示 unavailable，絕不暗中換 provider；所有 enabled provider 順序仍穩定；used/remaining 文字、VoiceOver、英／繁中與窄寬／notch 環境通過檢查；自動化測試證明 presentation 不改變 domain percentage、detector 或通知 threshold。

**Milestone B implementation（2026-09-01）**：已以 `UsagePresentation` 接入 Dashboard 主 percentage、VoiceOver 與單一選單列 metric；`MenuBarPresentation` 明確分離 persisted pin 與 currently rendered provider，unknown／disabled／unavailable pin 不會 fallback。人工驗證發現 Scene closure 曾捕捉 presentation value，導致 Settings 已持久化但選單列 label 未失效；修正後由共用 `SettingsModel` 擁有 runtime-observable presentation projection，label／content 在各自 `View.body` 直接觀察它。Settings 已用原生 `TabView` 拆為 General／Providers／Notifications，且不新增 network、timer、scheduler 或 provider I/O。後續 P0 又確認 Settings OFF 的舊路徑會明確正常終止 App；修正後以持續 Scene 保留 hidden process 與既有背景責任，explicit reopen 可復原，hidden login-item launch 則不建立 invisible process。Milestone B 在完整 menu lifecycle、light/dark、keyboard、VoiceOver 與真實選單列人工驗證完成前仍為未完成；Milestone C 暫停，不得提前開始。

### B. 可略過的首次啟動與可重看說明 — M

**問題**：source-build 使用者需要自行理解 Codex runtime、Claude 未驗證狀態、資料邊界與通知 permission，容易把 unavailable 誤解為錯誤。

**使用者收益**：隱私敏感或第一次使用者在 1–2 分鐘內知道「偵測到什麼、讀什麼、不讀什麼、接下來能做什麼」。

**實作輪廓**：單頁原生 sheet/window：歡迎、Codex runtime detected/not detected、Claude bridge configured/not configured、隱私摘要、Launch at Login、Display 及 pinned provider 預設。通知 permission 僅由使用者明確按鈕觸發；Skip 立即進 Dashboard；Settings 可重看，不重置任何 provider設定。

**依賴／架構**：重用 compatibility diagnostics 的 allowlisted detection snapshot；不得把 onboarding 變成 provider I/O 或 bridge installer。

**維護／隱私**：低；只保存 completed/dismissed preference，且不新增 telemetry。

**驗收條件**：fresh、Codex absent、Claude unconfigured、all providers disabled 與 permission denied 都可完成或略過；不存在「必須開啟通知」或「必須啟用 Claude」的阻塞；重看不覆寫既有選擇；可近用性、鍵盤、英／繁中、light/dark mode 均有驗證。

### C. Trusted Reset Intelligence Phase 1 — L

**問題**：本機 detector 能確認自己看到的新 cycle，卻無法讓使用者知道官方已宣布的全域 reset、temporary increase、banked reset 或 correction。

**使用者收益**：額度常受 rolling quota 限制的使用者能收到有來源連結的、保守的官方事件；這是比 history/chart 更直接可採取行動的資訊。

**實作輪廓**：演進 `ResetEvent` schema、cache 與 `ResetEventSource`；導入唯一的 static GitHub feed reader 與 event timeline/notification presentation。配對只使用新鮮 normalized local state：例如 verified「within next hour」事件可附「最新本機快照仍有 68% remaining」；eligible-account bonus 一律連回 eligibility/source，不說「你已取得」。correction/retraction 取代舊 revision，通知以 event ID + revision 去重。

**依賴／架構**：新增獨立 `ResetEventService`、bounded cache/state、Settings opt-in 與 feed repository/validation workflow。它不能依賴、阻塞或觸發 `UsageProvider`、Codex app-server 或 Claude snapshot reader。

**維護／隱私**：中等；需要 maintainer editorial review 與來源校對。網路請求僅取得公開 feed（仍會暴露一般網路連線 metadata，如 IP），沒有 QuotaPulse account、analytics 或 local usage upload。

**驗收條件**：每個顯示/通知事件可開啟原始 URL；feed unavailable/invalid/stale 時本機 quota 照常；correction/retraction 能安全取代且不重複提醒；事件、cache、response body 與 persistence 都有嚴格大小/版本限制；fixture 覆蓋 malformed/future schema、expiry、revision、dedup、audience mismatch、local snapshot stale 與 notification permission denied；透過手動 review 發布的少量 seed event 做端對端驗證。

## 精確實作順序

1. **Milestone A — v0.2 contract freeze**：先定義 feed schema/governance、display preference 的純 presentation boundary、Settings IA 與 onboarding state model；以 fixtures/tests 鎖定既有 detector/notification 不變。這先消除之後 schema 與設定 migration 的返工。
2. **Milestone B — Display + Settings**：實作 used/remaining、pinned provider、General/Providers/Notifications，完成 menu width/VoiceOver regression。這些純本機變更會提供 onboarding 的可設定目標。
3. **Milestone C — Onboarding（暫停）**：只有 Milestone B 的 P0 menu lifecycle 與剩餘人工驗證完成、並由使用者明確恢復 scope 後，才可重用 Milestone B 的 preferences 與既有 diagnostics snapshot；目前不得開始。
4. **Milestone D — Feed governance and reader**：先建立人工審核 static feed、schema validation、fixture、cache/ETag/expiry 與單一 coalesced fetch owner，再接 UI。先讓資料鏈可靠，才開始使用者可見的解釋。
5. **Milestone E — Conservative event/local matching and release evidence**：最後做 verified-event + fresh-local-snapshot 的可選文字與通知，並完成 no-upload、correction/retraction、notification dedup、offline 和低資源 soak 驗證。這避免 feed 還未可追溯時就誤導使用者。

## 明確不納入 v0.2 的三件事

1. **自動更新與 Sparkle**：沒有 signed/notarized binary 的前置條件時不做。
2. **Claude Code bridge 宣稱為正式支援**：缺少合格訂閱帳號與可逆 setup 的系統驗證；只做文件/fixture 維護。
3. **Usage history、charts 與 burn-rate ETA**：先證明同 cycle fresh samples 能產生可信粗粒度訊號，否則不保存資料或做圖表。

Gemini/OpenCode provider 擴張、右鍵 AppKit shell、GitHub Actions collector/backend、rotation/multiple provider menu title 也同樣不在本版。

## 散布建議

散布維持獨立 track：source-only → 可重現 Release build → Developer ID/Hardened Runtime/notarization/staple → signed/notarized ZIP 或 DMG → 只提示的 GitHub latest-release checker → custom Homebrew tap → 2–3 個穩定 binary releases 後才評估 Sparkle 2 與 official Homebrew Cask。

Apple Developer Program 的合理 trigger 不是單次 release，而是已出現重複「不想裝 Xcode」的外部回饋、約十位以上獨立使用者的安裝問題/需求、維護者願意承諾多個 binary releases，或 source-only 已明確成為持續使用的主要阻礙。屆時散布可以另開 v0.2.x 或專案 track；它不是本 v0.2 產品功能的 blocker。

## Claude 與其他 provider 建議

Claude 仍應維持 **Experimental / Unverified**。要進入正式 roadmap gate，至少需要：Claude Code 支援版本的真實 status-line fixtures、一個合格 Pro/Max（及必要時 Team/Enterprise）測試帳號、fresh profile/現有 `statusLine.command`/managed settings 的 preview-backup-restore 測試、atomic snapshot/permission/symlink hardening，以及實際 notification/freshness 行為證據。未滿足前不做 bridge 安裝器，也不改標籤。

Gemini CLI 目前只有互動式 `/stats model` 表面，OpenCode Go 有公開的方案 limits 但不是 QuotaPulse 可採用的安全 current-usage read contract。兩者都不值得以 credential、screen scraping、session 啟動、project server 或 token 推估來填補缺口。

## 版本建議與第一個實作任務

下一版應為 **v0.2.0**：它會新增可設定的日常 presentation、首次啟動流程與可選的外部 trusted feed，屬於明顯的新使用者能力，不是 v0.1.2 的修補。

第一個實作任務應是：**撰寫並核准 versioned `ResetEvent` feed schema/governance fixtures，同時列出 `SettingsStore` presentation/onboarding migration keys，但不接任何 network 或 UI。** 這先固定 v0.2 最高風險的資料合約與 privacy boundaries，讓後續 Display、onboarding 與 feed reader 不需要再搬遷資料模型。
