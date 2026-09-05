# QuotaMew post-v0.1 產品與技術策略

> 稽核日期：2026-08-30
> 範圍：目前工作樹中的產品、架構、測試、文件，以及公開競品與 macOS 發佈方案
> 性質：規劃文件，不代表未完成項目已實作或已驗證

## Executive decision

QuotaMew 不應成為通用 AI dashboard。它最有機會建立的產品信任是：在 macOS 選單列中，以很低的資源成本、清楚的資料來源與保守的判斷，回答「現在還剩多少、何時重設、這份資訊是否可信」。

建議的主要定位是：

> **The privacy-first AI coding quota menu bar.**
> **重視隱私的 AI coding 額度選單列工具。**

最多保留兩個次要差異點：

1. **可信任的 reset awareness**：通知依可驗證的 window／cycle 證據，不用單次百分比下降或過期快照猜測。
2. **透明的相容性與原生效率**：讓使用者知道 runtime 從哪裡來、上次刷新是否成功、為何不可用，同時維持單一排程與接近零的閒置 CPU。

「最輕量」可以是工程成果，但不適合當唯一定位；同類產品也會宣稱 native／lightweight。「告訴你下一步怎麼做」目前缺乏可靠 pacing 證據。「Reset Intelligence」有差異化潛力，但外部 feed 尚未建立可信來源治理，不應現在就成為主品牌承諾。

> 2026-08-31 更新：v0.1.1 已公開發行，且 completed-reset notification、production Diagnostics、disabled-provider semantics 與 MenuBar recovery 已實作。最新 v0.2 決策把可信 static feed 的第一階段 ingestion 列為範圍，但不代表 collector/backend/AI 自動發布已獲准；完整取代性決策見 [`V0_2_PLAN.md`](V0_2_PLAN.md)。

## 1. Current product health

整體判斷：**架構與隱私邊界健康，日常可用性與安裝可信度仍是 early-stage。**

### 已做得好的部分

- UI 只依賴 normalized domain state；provider DTO、process 與檔案格式都留在 adapter 邊界。
- Codex 使用 `codex app-server` 與 `account/rateLimits/read`，讓 Codex 自己持有驗證；不讀 `~/.codex/auth.json`。
- `CodexAppServerClient` 有 request coalescing、timeout、response size bound、process reuse 與清理路徑，健康時不會每次刷新都建立新 child process。
- `RefreshCoordinator` 合併重疊刷新；`AppModel` 是唯一 refresh／sleep task owner，provider 依序刷新，避免排程倍增。
- 失敗時保留仍有價值的 last-known snapshot，並以 freshness／錯誤狀態揭露不確定性。
- 通知採單一 `NotificationService`，有 bounded persistence、threshold 與 reset generation 去重；關閉 provider 或通知時會清除相符 pending request。
- 本機 reset detection 已採保守證據：長時間缺口重新建立 baseline、百分比下降本身不算 reset、過期／mock／缺乏 window identity 時不通知。
- Claude reader 只讀 legacy QuotaPulse-owned、版本化、大小受限的 snapshot；不掃 transcript、project cache 或 credential。
- English／繁體中文 String Catalog、VoiceOver label/value、鍵盤與 reduced-motion 已有明確測試／人工檢查邊界。
- SwiftUI previews 使用 mock provider；production assembly 使用真實 adapter，測試替身沒有混入 production path。

### 未完成或會直接傷害採用的部分

1. **source-only 發佈**：一般使用者需要 Xcode，且沒有 Developer ID、Hardened Runtime、notarization、安裝後 Gatekeeper 與 Launch at Login 驗證。
2. **缺乏首次啟動說明**：新使用者不知道 QuotaMew 讀什麼、不讀什麼、Codex 為何可能需要 ChatGPT.app，也不知道 Claude 目前需要尚未實作的 bridge。
3. **Claude Code 顯示大於實際可用性**：reader 與 UI 已存在，但 writer／可逆 setup／live subscribed-account validation 尚未完成。預設顯示「未設定」卡片容易被理解為產品故障。
4. **沒有 production diagnostics**：DEBUG 診斷不足以支援 GitHub 使用者；維護者無法快速區分 runtime discovery、app-server、資料可用性與 freshness 問題。
5. **disabled provider 語意不一致**：`UsageService` 已不呼叫 disabled provider，通知也已排除，但 Dashboard 仍渲染 disabled 卡片。
6. **更新與版本入口不足**：在可下載 binary 尚未存在前不應自動安裝，但未來 binary 需要清楚的版本、release 與更新路徑。
7. **缺乏持續整合證據**：本機測試很完整，但公開專案仍需要 PR build/test、Release build 與相容性 fixture 的可見狀態。

### 已存在但不夠容易發現

- 選單開啟時的 stale refresh、手動 refresh、last-updated／stale semantics 都已存在，但首次使用者不知道刷新政策與 failure fallback。
- Launch at Login、provider enablement、短／長視窗通知門檻都已有原生 Settings；沒有 onboarding 或簡短 privacy explanation 把它們串成可理解的 setup。
- approaching-reset 與 completed-reset 已共用單一通知邊界，但 UI 不容易讓人理解「接近重設」和「已確認重設」是不同證據。
- Claude 卡片會標示 Experimental／Unverified，卻沒有可完成的 bridge setup；狀態誠實但仍會讓使用者卡住。
- Codex locator 已支援 ChatGPT.app、legacy Codex.app 與 standalone executable 的安全順序，但使用者看不到最後採用哪一類 runtime。
- App 缺少容易找到的 version／build 與 privacy-safe diagnostics，issue 提交者只能描述「不能用」。

### 技術債與脆弱假設

- ChatGPT.app 內嵌 Codex runtime 是未文件化 packaging contract。現有 locator 的多路徑、trust 與 cache revalidation 做得謹慎，但 provider 更新可能改變 bundle 位置、executable 名稱或 protocol 行為。
- app-server initialization 中的 client version 必須跟 App release version 同步；硬編碼會隨版本漂移，之後應由 bundle metadata 提供。
- Claude status-line `rate_limits` 的 availability、版本與方案差異尚未完成 live matrix；在此之前只能維持 Experimental／Unverified。
- Settings 目前的 flat booleans 與 switch-based key mapping 對兩個 providers 很清楚；加入 display preference、pinned provider、onboarding state、diagnostics 後會開始難以掃讀與 migration-test。
- `MenuBarExtra(.window)` 很適合現在的資料卡片，但 SwiftUI 公開 API 沒有 secondary-click callback。為右鍵小選單改成 `NSStatusItem`／popover 會擴大 lifecycle、accessibility 與測試面。
- 目前效能數字是特定開發機與有限時段的觀察，不是硬保證；尚缺較長 Release soak 與 Intel Mac 驗證。
- 現有 release audit 的量測約為閒置 48 MB、開啟 menu／Settings 短暫接近 70 MB、閒置 CPU 接近 0%，但只代表記錄中的機器與約一小時條件；不得寫成所有 Mac 的保證。
- 自動化測試不能代替 live provider、系統通知、signed installed app、notarization 與 Gatekeeper 驗證，文件必須持續分開陳述。

### 不應因 v0.1 之後而改掉的決策

- 保持 native macOS、macOS 14+、Swift／SwiftUI／Foundation 與最少依賴。
- 保持一個 refresh owner、provider 順序刷新與 minute-granularity countdown；不加入全域一秒 timer。
- 不讀 credential、transcript、workspace、repository 或 session JSONL 作為正常資料來源。
- 不以 raw token totals 猜 subscription quota，也不以單次 percentage drop 判定 reset。
- provider-specific contract 留在 `Providers/<Provider>/`；UI 保持 normalized state。
- Claude 在 bridge 與 live validation 前維持 Experimental／Unverified。
- 外部 Reset Intelligence 與本機 snapshot／settings／provider adapter 分離，絕不上傳本機 usage。
- Production App Icon／branding refinement 目前延後；除非成為實際散布阻擋，post-v0.1 近期不投入 logo migration 工程。

### 可簡化或移除的項目

- Dashboard 不再顯示 disabled provider placeholder；重新啟用只在 Settings 管理。
- 不增加獨立的「Advanced」分頁來承載尚不存在的功能。
- 不新增第二套 notification scheduler、provider-specific UI branch 或 update daemon。
- 不把「Open QuotaMew」當成不明確命令；若未來出現此項，必須明確代表開啟現有 dashboard，而不是假裝有主視窗。

## 2. Primary users

| Persona | 核心問題與頻率 | 最有價值的資訊 | 可接受設定／安裝期待 | 會移除的原因 | 會推薦或 star 的原因 |
|---|---|---|---|---|---|
| Codex 日常重度使用者（首要） | 每天多次接近 5-hour／weekly limit | 剩餘或已用比例、可信 reset time、資料 freshness、reset 完成通知 | 幾乎零設定；期待簽章下載或 Homebrew | ChatGPT 更新後無聲失效、資訊過期卻像即時、安裝麻煩 | 一眼可信、故障可診斷、通知不誤報 |
| 多 AI coding 訂閱者（首要） | 每天在 Codex／Claude 間切換 | 各 provider 目前風險、最近 reset、固定 pinned provider | 可接受一次性的透明 setup；不接受 credential 匯入 | disabled／未設定卡片製造噪音、其中一個 provider 長期不可用 | 一個原生選單列就能理解多個額度，且 provider 互不拖累 |
| 隱私敏感的 macOS 開發者（核心影響者） | 長時間常駐，偶爾確認 | QuotaMew 讀取範圍、runtime source、last refresh、資源成本 | 期待 notarized App；設定要少且可撤回 | 掃描 logs／credentials、上傳 usage、背景 CPU 或記憶體失控 | 邊界寫得誠實、可複查、依賴少、Release 行為可驗證 |
| 開源 early adopter／貢獻者（次要） | 每次 release 或 provider breakage | build status、fixtures、known compatibility、issue diagnostics | 願意用 Xcode，但期待可重現 build 與清楚文件 | README 過度承諾、沒有 CI、issue 無法重現 | 架構清楚、測試扎實、相容性問題可小範圍修正 |

產品決策應先服務前三者；不能為了吸引「想看所有 token／成本／歷史圖表」的廣泛族群，把 QuotaMew 變成另一個通用 dashboard。

## 3. Required feature decisions

評分語意：User Value／Difficulty／Maintenance／Runtime／Privacy 均為 Low、Medium、High；milestone 是最早合理時間，不是承諾日期。

| Candidate | 分類 | User value | Difficulty | Maintenance | Runtime | Privacy | 建議 milestone | 決策 |
|---|---|---:|---:|---:|---:|---:|---|---|
| 更新系統（整體） | Should-have | High | Medium | Medium | Low | Low | v0.1.x–v0.2 | 先建立可信 binary，再做 release checker；自動安裝不應先於可信散布 |
| secondary-click 小選單 | Nice-to-have／Needs research | Low–Medium | High | Medium | Low | Low | v0.2 research | `MenuBarExtra` 無可靠公開 hook；不只為此遷移 AppKit shell |
| Settings 資訊架構 | Should-have | Medium | Medium | Low | Low | Low | v0.2 | 到新 preferences／diagnostics 造成現有 Form 必須明顯捲動時才拆分 |
| 選單列 provider selection | Should-have | High | Low–Medium | Low | Low | Low | v0.2 | 只做 icon-only 或一個 pinned provider；不 rotation／multiple／auto priority |
| Remaining vs Used | Should-have | Medium | Low | Low | Negligible | None | v0.1.x | 單純 presentation preference，domain 永遠只保留一套 normalized usage |
| disabled providers | Must-have | High | Low | Low | Positive | Positive | v0.1.x | Dashboard 隱藏；refresh／notification 已排除；Settings 是唯一重啟入口 |
| first-launch onboarding | Must-have | High | Medium | Medium | One-time | Low | v0.1.x | 單一、可略過、不阻擋 dashboard；不做 carousel |
| reset completed notification | Must-have／已實作 | High | Completed core | Medium | Low | Low | current working tree | 保守 local evidence 與 dedup 已存在；只剩 release-level 驗證與誠實文件 |
| official／bonus Reset Intelligence | Needs research | Medium today | High | High | Low | Low if separated | v0.3 research | 先手動維護、來源可追溯的 static feed；不可把 AI 摘要當權威 |

### 3.1 Update system

#### A. Sparkle 2 — 未來 Should-have，現在不導入

Sparkle 2 提供 appcast、背景檢查、下載與安裝流程；release archive 用 EdDSA 簽署，並可與 Apple code signing／notarization 形成兩層驗證。官方文件亦提供 SwiftUI 的 `SPUStandardUpdaterController`／Check for Updates 整合。這表示 LSUIElement menu-bar App 沒有明顯的框架級阻礙，但這是依其 programmatic integration 推論，仍須以實際 signed menu-bar build 驗證。

成本與風險：新增第三方 framework、appcast 發佈與 signing key lifecycle；還要測試 read-only volume、App Translocation、key rotation、失敗復原與舊版升級。Sparkle 不取代 Developer ID、Hardened Runtime 或 notarization。

採用門檻：至少有可重現的 signed／notarized binary pipeline，並完成 2–3 次穩定 binary release。之後再用 GitHub Pages 或靜態 release asset hosting appcast，開啟手動與背景檢查；自動下載／安裝必須另外取得使用者同意。

參考：[Sparkle documentation](https://sparkle-project.org/documentation/)、[Security and reliability](https://sparkle-project.org/documentation/security-and-reliability/)、[Programmatic setup](https://sparkle-project.org/documentation/programmatic-setup/)。

#### B. GitHub Releases API — 第一階段建議

第一個可下載、signed／notarized beta 出現後，先做低頻率（例如每日一次、支援 ETag）的 latest-release check；手動 Check for Updates 立即查詢，背景只顯示 update available 並開啟 GitHub Release 頁面，不在 App 內下載或安裝。GitHub 的 `releases/latest` 只回傳最新非 draft／prerelease 的正式 release，適合穩定 channel；beta 必須另定規則。

source-only 階段做 checker 的價值很低，因為使用者仍須拉 source／Xcode build。它應等第一個可信 binary，不要先為「有更新按鈕」增加網路面。

參考：[GitHub REST Releases API](https://docs.github.com/en/rest/releases/releases#get-the-latest-release)。

#### 更新互動的分階段判斷

| Capability | 決策 | 最早條件 |
|---|---|---|
| Check for Updates | Should-have | 第一個 signed／notarized binary；source-only 時只需 README／Release 連結 |
| Background update checks | Should-have、低頻且可關閉 | stable release channel 與 privacy disclosure 完成；使用 ETag／offline-safe behavior |
| Update available notification | Nice-to-have | 先用 menu／Settings badge；只有安全性更新需求證明不足時才用系統通知，且不干擾 quota 通知 |
| Automatic download | Defer | Sparkle 2、穩定 appcast、EdDSA key management 與數次 binary release 後，由使用者 opt-in |
| Automatic installation | Defer | signed／notarized archive、atomic replacement、rollback／translocation 測試全部通過後，由使用者 opt-in |

#### C. Custom updater — Reject

自行處理下載、簽章驗證、atomic replacement、rollback、權限與 App Translocation 的安全／維護成本，遠高於 QuotaMew 的產品價值。不要建立自訂 updater 或額外 launch daemon。

#### D. Homebrew — 安裝 channel，不是 App 更新核心

Custom tap 可在可信預建 archive 後提供便利；官方 Homebrew Cask 再依採用與維護能力申請。Cask 需要 version、SHA-256、下載 URL 與 `.app` artifact，且官方 cask 要符合 Gatekeeper 要求。它不替 QuotaMew 編譯 Swift，也不取代 Developer ID／notarization；只有透過 Homebrew 安裝的使用者由 `brew upgrade` 管理。

參考：[Homebrew Cask Cookbook](https://docs.brew.sh/Cask-Cookbook)、[Acceptable Casks](https://docs.brew.sh/Acceptable-Casks)。

#### 建議順序

```text
source-only
  → 可重現的 Release build
  → Developer ID + Hardened Runtime + notarization + staple
  → signed/notarized ZIP 或 DMG
  → GitHub latest-release checker（只提示／開啟 release）
  → custom Homebrew tap
  → 2–3 個穩定 binary releases
  → Sparkle 2 appcast／下載／安裝
  → 有持續採用後再評估官方 Homebrew Cask
```

Apple Developer Program 不需因單一 star 數字立即購買；但**一旦決定公開提供預建 App，membership 就是可信散布的前置條件**。可用的投入觸發是：維護者願意承諾至少數個 binary releases，且已出現重複的非 Xcode 安裝需求、約 10 位以上獨立使用者的安裝回饋／issue，或 source-only 明確阻擋持續使用。Apple 目前以 Developer ID 與 notarization 保護 App Store 外散布，年費與資格仍應在購買當下重新確認。

參考：[Apple Developer ID](https://developer.apple.com/developer-id/)、[Notarizing macOS software](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)、[Apple Developer Program](https://developer.apple.com/programs/)。

### 3.2 Menu bar interaction

- macOS 使用者說的「雙指點按」應視為系統設定映射出的 **secondary click**，不是 App 自訂 gesture。
- 目前 `MenuBarExtra(.window)` 已適合卡片式 dashboard；SwiftUI 公開 surface 沒有獨立 secondary-click callback。原生可靠實作通常要讓 AppKit `NSStatusItem`／`NSStatusBarButton` 擁有事件，再自行管理 popover／menu。
- 為了重複已有的 Settings／Quit 動作而遷移整個 menu shell，收益不足。先在現有 dashboard footer 加上必要的版本／更新入口即可。
- 若未來 pinned provider 需要動態 title、primary click dashboard、secondary click commands，才建立一個小型 AppKit spike，驗證 VoiceOver、鍵盤、menu tracking、sleep/wake 與 multiple-display 行為後決定是否遷移。

參考：[Apple `MenuBarExtra`](https://developer.apple.com/documentation/swiftui/menubarextra)、[Apple `NSStatusItem`](https://developer.apple.com/documentation/appkit/nsstatusitem)。

### 3.3 Settings information architecture

現在的單一 grouped `Form` 對 General／Providers／Notifications 仍可接受。最小可擴充結構是三頁：

1. **General**：Launch at Login、display used/remaining、pinned provider、版本／update。
2. **Providers**：enablement、detection、Claude bridge 狀態與 setup／remove（只有在實作後）。
3. **Notifications**：permission 狀態、總開關、approaching／completed-reset 類型與 thresholds。

Diagnostics 先做 General footer 的入口或獨立 sheet；不要為一個頁面建立「Advanced」tab。Display 只有 2–3 個 preference 時留在 General。遷移觸發是：一般視窗高度下需要明顯捲動才能理解主要設定，或 provider setup／notification permission 已具有獨立 state machine。

### 3.4 Menu bar provider selection

建議只支援：**Icon only** 或 **一個使用者固定的 pinned provider**。標題最多顯示 provider 短名／icon 加一個整數百分比，並在窄螢幕與 notch Mac 上測試。

不做：定時輪播（破壞肌肉記憶）、多 provider 長字串（擁擠）、依最近 quota 自動切換（介面不穩定且把不可靠風險判斷變成導航）。若 pinned provider 不可用，保持它並顯示 unavailable，不要偷偷切換。

### 3.5 Remaining vs Used

新增單一 `UsagePresentation` preference 即可；`UsageWindow` 仍維持同一份 normalized used／limit 表示，UI 在最後一步換算文字與 progress semantics。percentage、通知、reset detection 不得複製分支。VoiceOver value 與所有 provider card 必須同步切換。

### 3.6 Disabled providers

- Dashboard 對 disabled provider 不建立 card。
- `UsageService` 目前已不 fetch disabled provider；此行為保留並加 regression test。
- `NotificationService` 不為 disabled provider 建立新通知，且清理相符 pending request；此行為保留。
- Settings 保留 provider row 與重新啟用控制；空 dashboard 顯示一個簡短「在 Settings 啟用 provider」狀態即可，不逐一放 placeholder。

### 3.7 Minimal first launch

使用一個可略過的 compact window／sheet，不做長篇 carousel：

1. 歡迎與一句產品用途。
2. 偵測結果：Codex runtime detected／not detected；Claude bridge configured／not configured，並清楚區分「App 存在」和「usage 可讀」。
3. 預設選擇：Launch at Login、Remaining／Used、Icon only／pinned provider。
4. 隱私摘要：讀取哪些本機 quota surface；不讀 credential、prompt、transcript、project path，不上傳 usage；正常約 15 分鐘刷新與選單開啟時的 stale refresh。
5. Codex 說明 ChatGPT.app bundled runtime 是目前優先來源；Claude 標為 Experimental 並在 bridge 未完成時不誘導危險 workaround。

Notification permission 不應在 App 一啟動就突然跳出。onboarding 可解釋用途並提供明確按鈕，由使用者動作觸發系統 prompt；Skip 永遠直接進 dashboard，之後 Settings 可重新開啟 onboarding／privacy 說明。

### 3.8 Reset completed notification

目前工作樹已有 provider-agnostic local detection、cycle identity、long-gap rebaseline 與 persisted dedup。策略上它是 Must-have，但不應在 roadmap 假裝重新開發。交付前 acceptance：

- percentage decrease alone 永不通知。
- stale、malformed、missing reset、restart／reconnect 與 clock drift 不產生誤報。
- 同一 logical cycle 跨重啟最多一次 completed-reset 通知。
- disabled provider／notification 不執行或排程通知。
- fixture tests 與至少一次 opt-in live delivery 分開記錄。

### 3.9 Official／bonus Reset Intelligence

第一個可接受的 MVP 是 **maintainer-curated、GitHub-hosted static JSON feed**：

- schema 至少包含 stable ID、provider、event type、publisher、source URL、publication time、effective time/range、verification state、correction／retraction relationship 與 feed schema version。
- 每筆事件必須連回原始官方來源；App 顯示來源，不讓摘要取代來源。
- GitHub Action 只做 schema／URL／time validation 與產生 immutable artifact；人工 review 決定是否刊登。
- 規則優先分類；AI 只可協助維護者處理模糊候選，不能直接發布或成為 authoritative source。
- feed request 不含 local usage、provider state、workspace 或裝置識別。local notification matching 在 App 端進行。

不先做 social scraper、Cloudflare Worker 或資料庫。只有 static feed 出現修正延遲、來源量或可靠性瓶頸後，才評估 GitHub Actions collector；Worker／小型 backend 需要 uptime、abuse、cache、moderation 與成本責任，門檻更高。

目前 `ResetEvent` boundary 是好方向，但在 implementation 前要補齊 verification／correction／retrieval semantics 與 schema migration 設計；不得因已有 type 就宣稱 network feed 完成。

## 4. Additional opportunities

### Privacy-safe diagnostics — v0.1.x Must-have

這是目前最高報酬項目。production Diagnostics 應顯示並可複製：

- QuotaMew version／build、macOS version、architecture。
- 每個 provider 的 enabled、runtime detected、runtime source 類型（例如 ChatGPT.app；不含完整路徑）、app-server connected／disconnected。
- last refresh time 與 success／failed、usage available yes／no、snapshot freshness category。
- Claude bridge schema／configured 狀態；不複製 command 或檔案路徑。

Copy Diagnostics 必須由 typed allowlist 生成，不可先 dump object 再 redact。禁止 credential、prompt、transcript、project path、session、token、raw provider payload、完整 process output 與原始 error body。這同時提升使用者理解、issue 品質與未文件化 runtime breakage 的可維護性。

### Pacing／burn rate — Needs research

本機推導有潛在價值，但只有在同一可信 cycle 內累積足夠多個 fresh samples，且 reset／gap／provider schema 都可辨認時才成立。第一步是離線 fixture prototype，用粗略狀態「On pace／Faster than window pace／Insufficient data」，不要顯示「2h 40m」式假精準 ETA。

若無法在 provider reset、睡眠長缺口、跨裝置使用、bonus reset 下保持低誤判，就不實作。任何 samples 必須 bounded、local、可關閉，且不成為外部 Reset Intelligence payload。

### Usage history — Defer

歷史圖表不是目前核心問題，會增加 persistence migration、privacy explanation、disk bounds 與 UI 複雜度。若 pacing research 需要資料，先保存最小、短期、bounded 的 normalized samples（例如固定上限的 7 天 JSON ring），不要直接導入 SwiftData／SQLite 或 dashboard charts。使用者可見 history 只有在研究證明會改變行為後再評估，且應 opt-in／可清除。

### Provider ordering — Nice-to-have later

兩個 provider 不值得 drag-and-drop。達到至少三個可用且可同時啟用的 provider，再以 Settings 的 Move controls／drag ordering 評估；Dashboard 使用穩定 order，不因風險自動排序。

### Status／risk indicator — v0.2 Should-have with constraints

可從已存在資料建立 `Unavailable`、`Stale`、`Near limit`、`Reset soon`、`Healthy` 等互斥語意狀態，但門檻要少、文字化且可測試。不要加入裝飾性 score、彩色儀表或把缺資料標成危險。若同時顯示 usage 與 reset approaching 已足夠，就不必額外增加 badge。

### Compatibility database — local first

v0.1.x 先在 GitHub 文件維護「last validated ChatGPT version／bundled Codex version／macOS／architecture」matrix，搭配 diagnostics 與 issue template。App 只顯示實際偵測版本和已知本地狀態。

只有同一種 packaging breakage 重複發生、且文件更新速度不足，才研究小型 signed remote manifest。manifest 只能描述 version compatibility，不回傳本機 usage；必須有 cache、expiry、schema version、signature、失敗時不阻擋 provider 的設計。

## 5. Priority comparison

分數 1–5 只用來比較。User Value／Differentiation 越高越好；Cost／Risk 越高越昂貴或危險。Overall 是有條件的產品判斷，不是精密公式。

| Proposal | User Value | Differentiation | Implementation Cost | Maintenance Cost | Privacy Risk | Performance Risk | Reliability Risk | Overall |
|---|---:|---:|---:|---:|---:|---:|---:|---|
| Privacy-safe diagnostics | 5 | 4 | 2 | 2 | 1 | 1 | 1 | Highest |
| Hide disabled providers | 4 | 1 | 1 | 1 | 1 | 1 | 1 | Highest quick win |
| Signed/notarized binary pipeline | 5 | 4 | 4 | 4 | 1 | 1 | 3 | Highest, externally gated |
| Minimal onboarding | 4 | 2 | 3 | 2 | 1 | 1 | 2 | High |
| Used/remaining + one pinned provider | 4 | 2 | 2 | 2 | 1 | 1 | 2 | High |
| Public CI + compatibility matrix | 4 | 3 | 2 | 3 | 1 | 1 | 2 | High maintenance foundation |
| GitHub release checker | 3 | 1 | 2 | 2 | 1 | 1 | 2 | Medium-high after binary |
| Claude opt-in bridge | 4 | 3 | 4 | 4 | 3 | 1 | 4 | High value, gated research |
| Sparkle automatic updates | 4 | 1 | 3 | 3 | 1 | 1 | 3 | Medium, after stable releases |
| External Reset Intelligence | 3 | 5 | 4 | 5 | 2 | 1 | 5 | Strategic research, not immediate |
| Pacing／burn rate | 4 | 3 | 4 | 4 | 2 | 2 | 5 | Research only |
| Usage history／charts | 2 | 1 | 4 | 4 | 3 | 3 | 3 | Defer |
| Gemini／OpenCode expansion | 3 | 1 | 4 | 5 | 3 | 2 | 5 | Defer until contracts exist |

## 6. Maintenance roadmap (not product features)

| Cadence | Maintenance work | Evidence／exit condition |
|---|---|---|
| Every PR | Debug tests、unsigned Release build、localization key tests、notification/reset regression | CI checks green；失敗不以人工口頭略過 |
| Every QuotaMew release | clean build、unit tests、signed artifact verification（binary 階段）、Gatekeeper、notification opt-in、Launch at Login | Release checklist 附版本、machine、macOS、結果與未驗證項目 |
| Every ChatGPT／Codex compatibility report | locator fixture、app-server handshake／schema、process cleanup、last-good behavior | 更新 public compatibility matrix；issue 附 allowlisted diagnostics |
| Claude contract change／每季 | status-line schema、bridge setup／restore、freshness 與 future-version fixtures | fresh profile 與 existing statusLine profile 都可回復；否則維持 Unverified |
| Quarterly Xcode／macOS review | Swift language mode、deprecated API、MenuBarExtra／SMAppService／UserNotifications behavior | 支援基線或文件更新；不偷偷擴大 deployment target |
| Every UI change | English／zh-Hant strings、VoiceOver、keyboard、light/dark、narrow width | String Catalog 無遺漏；人工 UI evidence 與 unit tests 分列 |
| Every persistence change | size bound、migration、malformed／oversized／future version、atomicity | no unbounded history；reset／notification state 可安全 rebaseline |
| Before performance claim／each stable binary | Release 8–24 hour soak、menu/settings transient、sleep/wake、Intel if supported | 記錄 idle CPU／memory／條件；不把單機觀察寫成保證 |
| Dependency introduction | license、size、privacy、maintenance、security update path | 書面 rationale；Sparkle 是目前唯一可預見的候選 runtime dependency |
| Monthly／release | GitHub issue templates、security policy、dependency／secret scanning 能力複查 | 不上傳敏感 diagnostics；finding 有 owner 與處理狀態 |

## 7. Open source and monetization

建議立場：**先建立可信任的免費產品與散布流程，營利延後。** 核心 quota visibility、privacy、基本 approaching／completed-reset 通知不應為了付費層而刻意變差。

| Model | MIT fit | 付費可能性 | Cost／complexity | Privacy／trust | Fork bypass | Recommendation |
|---|---|---|---|---|---|---|
| 完全免費 + GitHub Sponsors／donations | 完全相容 | Low–Medium | Very low | Positive | 不適用 | 最適合近期；有使用者後再開啟 |
| 免費 source + 付費 signed/notarized binary | 相容，source 仍可自行 build | Medium for convenience | Low–Medium | 容易被視為對安全性收費 | High | 不作近期主模式；安全更新與官方 binary 不宜成為人為摩擦 |
| 免費 local App + 付費 hosted Reset Intelligence | 相容，服務可獨立 | Unknown | High editorial／uptime | usage 不上傳時可控，但來源信任高風險 | Medium | 只有免費 feed 已證明需求後再研究 |
| Personal free + Team／Organization | 相容 | Low today | Very high accounts／cloud／admin | High | Medium | Reject for current product；會把產品推向 generic dashboard |
| Paid support／priority compatibility | 相容 | Medium for organizations | Low hosting、High SLA burden | Neutral | Low | 未來有組織採用時可行 |
| Paid advanced provider integrations | 法律／技術依 provider 而定 | Unknown | High | 常涉及 credential／private API | High | Avoid unless official contract clearly permits |
| Open core + proprietary service | 相容但需界線清楚 | Unknown | High | Community reaction mixed | Medium | 只有獨立服務有不可複製營運價值時再評估 |

MIT 允許 fork、修改、重散布與商業使用，因此 client-side premium lock 幾乎沒有可靠護城河，還會降低信任。現階段不另建 `MONETIZATION.md`；等 signed distribution 與持續使用者訊號出現，再以 Sponsors／support 為優先，而不是鎖住核心功能。

## 8. Realistic roadmap

### v0.1.x — Polish／Adoption／Compatibility

#### Privacy-safe Diagnostics + Copy Diagnostics

- Problem：runtime／app-server／freshness failure 無法由使用者與維護者快速區分。
- Target：所有 persona，尤其公開 GitHub 使用者。
- Priority：P0。
- Dependencies：typed allowlist diagnostics model；現有 locator／provider state。
- Implementation risk：Low–Medium；避免 diagnostics 本身觸發昂貴 refresh。
- Maintenance risk：Low；每個新 provider 要補 allowlist。
- Acceptance：不含任何 path／credential／prompt／transcript／session／token／raw payload；fixture test 證明輸出穩定且可貼入 issue。

#### Disabled provider dashboard semantics

- Problem：已停用 provider 仍佔據 dashboard，與「不刷新／不通知」語意不一致。
- Target：單 provider 使用者與隱私敏感使用者。
- Priority：P0 quick win。
- Dependencies：現有 enablement state。
- Implementation risk：Low；需處理全部 disabled 的 empty state。
- Maintenance risk：Low。
- Acceptance：disabled provider 不 render／fetch／schedule；Settings 可重新啟用；empty state 只有一個明確入口。

#### Public CI and compatibility foundation

- Problem：本機驗證強，但外部貢獻／provider regression 缺少可見 guardrail。
- Target：維護者、貢獻者、遇到 breakage 的使用者。
- Priority：P0 maintenance。
- Dependencies：可重現的 unsigned build/test command、redacted fixtures。
- Implementation risk：Medium；macOS runner／Xcode 版本可能漂移。
- Maintenance risk：Medium。
- Acceptance：PR 執行 tests + Release compile；fixture／localization／reset dedup failures 阻擋合併；live system check 明確不冒充 CI。

#### Minimal first-launch onboarding

- Problem：資料來源、provider readiness、privacy 與基本 preference 不可發現。
- Target：第一次安裝的 Codex／多 provider 使用者。
- Priority：P1，必須早於公開 binary。
- Dependencies：provider detection、settings migration、diagnostics wording。
- Implementation risk：Medium；不能阻塞 App 或過早要求 notification。
- Maintenance risk：Medium；每個 provider contract 變動都要更新 copy。
- Acceptance：可略過／重開；離線可用；明確說明 reads／does-not-read；設定失敗不阻擋 dashboard。

#### Remaining／Used presentation preference

- Problem：不同使用者對「剩餘」或「已用」有不同掃讀習慣，但目前呈現固定。
- Target：所有日常使用者。
- Priority：P1 quick win，可與 onboarding 共用選擇。
- Dependencies：單一 typed display preference 與 migration default。
- Implementation risk：Low；必須同時更新文字、progress semantics 與 VoiceOver value。
- Maintenance risk：Low。
- Acceptance：domain／notification／reset detector 不增加第二套計算；所有 provider 使用相同 preference；切換後數值互補且 accessibility 一致。

#### Current reset-completed work release hardening

- Problem：已實作能力需從 fixture confidence 走到 release evidence。
- Target：常接近 rolling limit 的使用者。
- Priority：P1 validation，非新功能重做。
- Dependencies：現有 detector／notification tests。
- Implementation risk：Low；主要風險是過度宣稱 live coverage。
- Maintenance risk：Medium，provider window contract 會漂移。
- Acceptance：conservative regression suite green；一次 opt-in 系統 delivery 獨立記錄；README 不把未驗證 provider 寫成 verified。

### v0.2 — Product Experience／Trusted Distribution

#### Signed/notarized downloadable App

- Problem：source-only 是最大安裝摩擦與信任缺口。
- Target：不使用 Xcode 的一般開發者。
- Priority：P0，受 Apple membership 與維護承諾 gate。
- Dependencies：Developer ID、Hardened Runtime、notary pipeline、artifact／Gatekeeper checklist。
- Implementation risk：High；entitlements、SMAppService、nested runtime execution 都要以 installed App 驗證。
- Maintenance risk：High；每個 release 都需持續完成。
- Acceptance：fresh Mac 可下載、驗證、開啟、刷新、Launch at Login；`spctl`／staple／signature evidence 留存；source build 仍免費。

#### GitHub release checker

- Problem：binary 使用者不知道何時有相容性／安全性更新。
- Target：GitHub direct-download 使用者。
- Priority：P1 after binary。
- Dependencies：穩定 release/version policy、network privacy disclosure。
- Implementation risk：Low–Medium；rate limit、offline、prerelease semantics。
- Maintenance risk：Low–Medium。
- Acceptance：手動 check、低頻背景 check、清楚 offline state；只開 release page，不下載／安裝；Homebrew install 不被誤導。

#### Scalable settings + pinned provider presentation

- Problem：新增 onboarding、display、pinned provider、diagnostics 後單頁 Form 失去可掃讀性。
- Target：多 provider／日常自訂使用者。
- Priority：P1。
- Dependencies：typed preferences 與 migration tests。
- Implementation risk：Medium；settings state 不能散落到 UI。
- Maintenance risk：Low–Medium。
- Acceptance：最多 General／Providers／Notifications 三頁；既有 Used／Remaining 仍是 presentation-only；一個 pinned provider 穩定顯示且通過 narrow-width／VoiceOver。

#### Claude opt-in bridge completion

- Problem：Claude 卡片目前無法在乾淨安裝中自己產生 snapshot。
- Target：同時訂閱 Claude Code 的使用者。
- Priority：P1，但必須先完成 live research。
- Dependencies：官方 status-line contract、preview／backup／restore、fresh + existing configuration matrix。
- Implementation risk：High；不能覆寫使用者現有 command 或誤讀方案 quota。
- Maintenance risk：High；Claude schema／availability 可變。
- Acceptance：setup 明確 opt-in、可預覽／移除／恢復；只寫最小 rate-limit snapshot；live subscribed-account evidence 完成前仍標 Unverified。

### v0.3 — Reset Intelligence research

#### Curated static ResetEvent feed MVP

- Problem：官方 bonus／global reset 不一定能由本機 rolling window 推導。
- Target：遭遇臨時官方額度事件的重度使用者。
- Priority：P2 strategic experiment。
- Dependencies：可信來源 policy、event schema、correction／retraction、network privacy review、maintainer coverage。
- Implementation risk：High；來源語意與時區容易誤導。
- Maintenance risk：Very high；需要持續 editorial ownership。
- Acceptance：每筆有 publisher／source URL／publication／effective／verification；App offline／feed failure 不影響 local provider；沒有 local usage upload；AI 不直接發布。

#### Coarse pacing experiment（不保證交付）

- Problem：百分比本身未回答是否會在 reset 前耗盡。
- Target：用量變化大的重度使用者。
- Priority：P3 research。
- Dependencies：同 cycle 多個可信 samples、confidence rules、bounded local retention。
- Implementation risk：High。
- Maintenance risk：High。
- Acceptance：在 sleep gap／reset／跨裝置不確定時輸出 insufficient data；不顯示假精準 ETA；若離線評估誤判率不可接受即停止。

### Long-term／research only

- Sparkle 2：完成 2–3 個 signed releases 後再導入。
- remote compatibility manifest：只有 documented matrix 無法及時處理重複 breakage 時。
- Gemini／OpenCode：只有文件化、安全、bounded quota contract 存在時。
- 使用者可見 history／charts：只有 pacing research 證明行為價值時。
- official Homebrew Cask：已有穩定 binary、可持續 release cadence 與足夠 adoption 後。
- Production App Icon／branding refinement：目前 deferred polish，不列入近期工程。

## 9. Recommended next five

1. **Privacy-safe Compatibility Diagnostics**：低成本直接改善理解、issue 品質與 runtime breakage 修復速度，是使用者價值、可信度與維護性的最佳交集。
2. **Trusted Binary Distribution Foundation**：先完成 CI／release checklist，再以 Developer ID、Hardened Runtime、notarization 交付真正可安裝 App；它比再加一個功能更能擴大實際使用。
3. **Minimal First-launch Onboarding**：把 provider detection、privacy、refresh cadence 與三個必要選擇放在一個可略過流程，降低「裝了但不知道為何不可用」。
4. **Provider Visibility and Presentation Coherence**：隱藏 disabled provider、加入 Used／Remaining 與一個 pinned provider；用小範圍 preference 解決每天都看得到的摩擦，不複製 quota logic。
5. **Claude Opt-in Bridge Validation and Completion**：先以官方欄位、可逆設定與 live matrix 驗證，再讓第二個已宣告 provider 真正可用；這比立即擴展 Gemini／OpenCode 更能建立產品誠信。

## 10. Explicitly do not build yet

1. **外部 automated Reset Intelligence backend／collector**：先證明來源治理、人工 static feed 與維護責任；否則差異化會變成誤報風險。
2. **Burn-rate ETA、長期 history 與 charts**：目前資料不足以支持精準預測，且會破壞 minimalist／privacy positioning。
3. **Gemini、OpenCode 或大規模 provider expansion**：先讓 Codex 安裝／相容性與 Claude bridge 成熟；沒有文件化 quota contract 就不加入。

另不建議以 custom updater、credential／cookie access、transcript scanning、automatic provider rotation 或 xattr quarantine bypass 充當捷徑。
