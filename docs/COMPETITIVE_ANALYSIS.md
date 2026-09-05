# QuotaMew 競品與相鄰產品分析

> 研究日期：2026-08-30
> 來源範圍：公開 repository、README、release／安裝文件與可見 license；未複製任何競品原始碼
> 注意：stars、release 狀態與安裝方式會變動，採用實作方向前需重新確認

## Summary

同類工具已證明幾件事：使用者會為「一眼看到 quota」安裝 menu-bar App；signed／notarized download、Homebrew、onboarding 與可診斷性，比堆疊圖表更能降低採用摩擦；burn-rate／pacing 是明顯的新興需求。

但許多工具也用 QuotaMew 不應接受的方式換取「零設定」或 provider breadth：讀 credential、cookie、session log、private endpoint，安裝 unsigned App 後要求 `xattr -dr com.apple.quarantine`，或把 token／cost／activity／account switching 全塞進同一個常駐 dashboard。

QuotaMew 應採用的是產品模式，不是資料擷取捷徑：compact presentation、first-run detection、doctor／diagnostics、可信 binary 發佈、低頻更新提示。其架構身份應繼續是 provider-owned authentication、normalized state、bounded local data 與保守 failure。

## Competitor matrix

| Project | Installation／updates | Providers／data source | Menu／dashboard | Prediction／history | Privacy／performance posture | License／maintenance signal | Useful lesson | Main concern for QuotaMew |
|---|---|---|---|---|---|---|---|---|
| [Pelu](https://github.com/TobyWu666/pelu) | signed／notarized macOS release、Sparkle；另有 iPhone | Codex app-server + session JSONL fallback；Claude status-line；CloudKit private DB | macOS dashboard、widgets、Live Activity | 30-day history、cost | 宣稱無自有 backend；使用 Apple private CloudKit | MIT；範圍跨 macOS／iOS | onboarding detection、完整 release pipeline、可逆 status-line setup | 不複製 iPhone／cloud/history 或 undocumented JSONL fallback；維護面太大 |
| [Codex Monitor](https://github.com/burakereno/codex-monitor) | signed／notarized DMG；one-click update | Codex app-server | 5-hour／weekly／credits，多 display modes，Dock 可選 | 無核心 history | native macOS 14，local | repository 頁面未見明確 license；採用任何實作前須先釐清 | Codex-only 的聚焦、安裝與 display mode | 無 license 時只能參考公開 UX 概念，不能移植程式碼或具體實作 |
| [Coding Usage Bar](https://github.com/hanzhangzzz/coding-usage-bar) | npm／Node 20 + SwiftBar + launchd；`doctor`／`--fix` | 多 provider；Claude status-line wrapper；部分 provider 使用 API key／credential surface | 高資訊密度 menu-bar line、notification cards | pacing 狀態 | 本機 runtime files；架構含多個外部工具 | MIT；文件與維修命令完整 | doctor、consent／restore flow、pacing 的粗粒度語言 | 不複製 Node／SwiftBar daemon、寬 menu title、credential-driven breadth |
| [CodexQuotaBar](https://github.com/Marchfool/codex-quota-bar) | GitHub build／ad-hoc；文件含 quarantine workaround | 多 provider、API balance、memory、task activity；會使用 auth、cookie、JSONL／local logs | 多卡片、widget、activity／memory sparkline | token／memory history | 資料面非常廣，含 browser／local session surfaces | MIT | 顯示多種狀態的 discoverability | credential/cookie/log access、generic dashboard、Gatekeeper bypass 都違反 QuotaMew 邊界 |
| [ClaudexBar](https://github.com/ipangdz/claudexbar) | Homebrew prebuilt、source one-liner；CLI updater launch agent | Codex + Claude；可從 auth／Keychain／OAuth surface 取得資料 | AppKit compact menu；right-click commands；依前景 App／session 自動切換 | 無核心 chart | native，強調 zero-config | MIT | compact AppKit interaction、安裝便利 | 不監控使用者 activity、不讀 credential、不自動切 provider、不自製 updater daemon |
| [TokenBar](https://github.com/Nanako0129/TokenBar) | GitHub／Homebrew；Sparkle；部分流程仍為 ad-hoc／quarantine handling | 25+ agents／CLIs、local logs、Rust FFI | 七種 dashboard lenses、token／cost／live rate、3D charts | 大量歷史與視覺分析 | local-first，但 source breadth 很大 | MIT；公開頁面顯示大量 commits、stars／forks 與 Patreon | breadth／visual polish 能帶來 GitHub discoverability；Sparkle 可與 Homebrew 共存 | 不追求 25 providers、3D charts、Rust FFI 或 token analytics；相容性成本不符合定位 |
| [Usage Bar (johnkueh)](https://github.com/johnkueh/usage-bar) | signed／notarized DMG、Sparkle daily signed updates | 多 provider、accounts；Codex app-server，部分 provider credential／OAuth | native first-run welcome、menu refresh、last-good state | 非主打 | native、local；無自有 quota backend | MIT | first-run welcome、signed distribution、last-good freshness | 不承擔 multi-account credential management；更新只在可信 binary 後採用 |
| [UsageBar (peerb)](https://github.com/peerb/usage-bar) | Homebrew tap／source build；unsigned 流程要求移除 quarantine | Codex + Claude；讀 Claude cache／credential/API surface | 極簡兩條 quota bars | 無 | 小型 native App | MIT | 兩個 bars 的 glanceability | 不採用其 private／credential data surface 或 unsigned 發佈捷徑 |

## Per-project findings

### Pelu

Pelu 的產品範圍最完整：macOS／iPhone、widgets、Live Activity、history、cost、onboarding、Sparkle 與 signed/notarized workflow。它顯示「新使用者先偵測 provider，再清楚解釋 setup」與「release artifact 可直接安裝」很有價值。

它也顯示範圍失控的維護代價：CloudKit、iOS lifecycle、history migration、cost model 與多種 fallback 都不是 QuotaMew 近期核心。Codex session JSONL 即使作 fallback，仍有 stale／schema／privacy 風險；QuotaMew 應保留 app-server-first 且安全 unavailable 的策略。

### Codex Monitor

Codex Monitor 聚焦單一 provider，提供 5-hour／weekly／credits 與多種顯示模式，並直接提供 signed／notarized DMG。這證明 source-only 是 QuotaMew 的競爭劣勢，也支持 Remaining／Used 與 menu display preference。

公開 repository 頁面未見明確 license 時，不能假設可重用 source 或具體架構。QuotaMew 只應採用通用產品概念，並以自己的 normalized model 實作。

### Coding Usage Bar

最值得採用的不是其 Node／SwiftBar stack，而是 `doctor` 思維：偵測缺少的 provider、解釋問題、提供可復原的修正。Claude status-line wrapper 的 consent、backup／restore 與 manual instructions 也是良好產品模式。

它的 pacing 用粗粒度狀態比假精準 ETA 更適合研究。但 QuotaMew 不應為此加入 launchd daemon、5-minute Node process、寬而容易被 notch 擠掉的 menu title，或為 provider breadth 導入 credential／API key 管理。

### CodexQuotaBar

這類「一次顯示 quota、API balance、memory、task activity、session history」的工具很容易吸引 GitHub 注意，卻會把產品變成 generic dashboard。尤其 auth file、browser cookie、hidden web view、JSONL logs 與 quarantine bypass，和 QuotaMew 的 provider-owned authentication、最小資料與可信散布原則直接衝突。

### ClaudexBar

AppKit `NSStatusItem` 使 primary／secondary click 與 compact menu 更容易控制；這可作未來 menu-shell spike 的參考。Homebrew 安裝也降低 friction。

但 foreground app／session activity 自動切 provider 會讓選單列不穩定，還擴大 workspace privacy surface。CLI updater launch agent 也新增第二個 lifecycle owner。QuotaMew 若要右鍵，應先證明互動價值足以支付 AppKit migration，而不是照抄。

### TokenBar

TokenBar 展示 breadth、charts 與高活動 repository 對 GitHub discoverability 的效果；也說明 Sparkle、Homebrew 與 sponsorship 可以共存。

然而 25+ integrations、log ingestion、Rust FFI、七種 dashboard 與 3D chart 需要完全不同的產品／維護模型。QuotaMew 應用更少的 provider 做出更可驗證的 quota contracts，不與 TokenBar 比功能數量。

### Usage Bar projects

johnkueh/usage-bar 的 signed／notarized DMG、first-run welcome、Sparkle daily update 與 last-good display 是值得參考的完整體驗。peerb/usage-bar 則證明極簡兩條 bar 就能清楚傳達 quota。

QuotaMew 不應跟進 account switching、credential management 或 undocumented Claude API；也不應要求一般使用者執行移除 quarantine 的 shell command。

## Cross-competitor lessons worth adopting

### 1. 安裝可信度是產品功能

多個活躍工具提供 DMG、Homebrew 或 app updater。QuotaMew 的架構品質無法彌補「必須有 Xcode」的第一步。正確順序是 signed／notarized artifact、可重現 release checklist，再加入 release checking／Sparkle。

### 2. First-run detection 比長 README 更能降低困惑

偵測 runtime、顯示 available／not configured、說明資料邊界與提供可略過設定，是跨產品最穩定的 UX 模式。QuotaMew 應以單頁 onboarding 和 Diagnostics 共用同一份 detection model。

### 3. Doctor／Copy Diagnostics 是開源維護槓桿

provider packaging 不穩定時，privacy-safe diagnostics 會把「不能用」轉成可重現的 version／state 報告。這比在 App 內塞更多 fallback 更可靠。

### 4. Compact display preferences 有日常價值

Used／Remaining、icon-only／one pinned provider 可改善每一次查看；它們不需要新資料來源，也不改變 domain calculation。

### 5. Pacing 值得研究，但應用信心而非精準數字

競品顯示使用者想知道「會不會在 reset 前用完」。QuotaMew 的版本必須以同 cycle 多筆 fresh sample、粗粒度結果與 insufficient-data state 為前提。

### 6. GitHub appeal 來自可見可信度，不只 feature count

可安裝 release、真實 screenshots、CI badge、清楚 privacy table、compatibility matrix、good-first-issue 與高品質 issue diagnostics，比再列十個 planned providers 更能讓目標使用者 star／推薦。screenshots 必須來自真實 App，不製造 mock product evidence。

## What QuotaMew should deliberately NOT copy

1. **Credential／cookie／private API ingestion**：不讀 `auth.json`、Keychain token、browser cookie 或未文件化 OAuth usage endpoint。
2. **Transcript／session log scanning**：不掃 Claude project transcripts、Codex session JSONL、workspace activity 或 prompt history來換取「零設定」。
3. **Generic token／cost dashboard**：不擴展為模型 token、API 帳單、記憶體、task activity、streak 或 productivity analytics。
4. **Provider-count race**：沒有文件化 quota contract、fixtures、failure semantics 與維護 owner，就不加入 provider。
5. **擁擠或會自行變動的 menu title**：不輪播、多 provider 並排或依前景 App／nearest limit 偷偷切換。
6. **未證實的 ETA／精美歷史圖**：不以跨裝置、缺口或 stale samples 做「還可用 2h 40m」假精準預測。
7. **Unsigned distribution workarounds**：不把 `xattr -dr com.apple.quarantine`、右鍵 Open 或 ad-hoc signing 當正式安裝體驗。
8. **Custom updater／第二個 daemon**：不自行處理 App replacement，也不讓 launchd／provider CLI 更新形成另一套 scheduler。
9. **Cloud／iPhone expansion**：不為了 feature parity 提前加入 accounts、CloudKit、sync、widgets 或 Live Activities。
10. **不透明 AI classification**：AI 可以協助維護者分類公告，但不能自動成為 Reset Intelligence 的 publisher 或權威來源。

## License and architecture adoption rule

- MIT 專案可在保留 license／copyright 的前提下依法研究與重用，但 QuotaMew 仍應優先保留自己的 adapter／domain boundaries，避免不必要的 source copying。
- 未見 license 的 repository 視為 all rights reserved；只討論一般 UX idea，不複製 code、assets 或具體表達。
- non-commercial、source-available 或自訂 license 不等同 open source；採用前逐項確認。
- 即使 license 允許，讀 credentials、logs、cookies、維持 daemon 或導入 FFI 仍須通過 QuotaMew 的 privacy、runtime、size 與 maintenance 評估。

## Research sources

- [Pelu repository](https://github.com/TobyWu666/pelu)
- [Codex Monitor repository](https://github.com/burakereno/codex-monitor)
- [Coding Usage Bar repository](https://github.com/hanzhangzzz/coding-usage-bar)
- [CodexQuotaBar repository](https://github.com/Marchfool/codex-quota-bar)
- [ClaudexBar repository](https://github.com/ipangdz/claudexbar)
- [TokenBar repository](https://github.com/Nanako0129/TokenBar)
- [Usage Bar repository](https://github.com/johnkueh/usage-bar)
- [UsageBar repository](https://github.com/peerb/usage-bar)
- [Sparkle 2 documentation](https://sparkle-project.org/documentation/)
- [Apple Developer ID](https://developer.apple.com/developer-id/)
- [GitHub Releases API](https://docs.github.com/en/rest/releases/releases)
- [Homebrew Cask Cookbook](https://docs.brew.sh/Cask-Cookbook)
