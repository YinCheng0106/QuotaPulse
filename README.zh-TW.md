# QuotaPulse

[English](README.md) | **繁體中文**

QuotaPulse 是一款輕量、原生的 macOS 選單列工具，用來監看 AI 程式開發代理工具的額度用量與重設時間。

## 畫面預覽

實際 App 畫面截圖刻意延後，之後再加入。目前 README 不會連結到暫代圖片。

## 為什麼需要 QuotaPulse

不同程式開發代理工具的額度可能在不同時間重設。QuotaPulse 讓目前用量百分比、重設時間與倒數只要點一下就能看到，不需要 QuotaPulse 帳號或雲端服務。

## 功能

- 使用 Swift 與 SwiftUI 開發的原生 macOS 選單列 App
- Codex 已使用與剩餘額度百分比
- 重設時間與分鐘級倒數
- 透過 macOS 通知提供本機重設提醒
- 精簡的「設定」，可控制登入時啟動、provider 啟用狀態與提醒門檻
- 不含私密資訊的相容性診斷，可複製適合貼到 GitHub Issue 的報告
- 英文與臺灣繁體中文本地化
- 為輕量長時間執行設計的保守刷新排程
- 隱私優先的本機處理，且沒有第三方 runtime 相依套件

## 支援的 providers

| Provider | 狀態 | 整合方式 |
| --- | --- | --- |
| Codex | **Supported** | 已使用 ChatGPT.app 內附的 Codex runtime 驗證；探索時也保留舊 Codex.app 與相容獨立 CLI 位置作為 fallback。 |
| Claude Code | **Experimental / Unverified** | 已實作有大小上限的本機 snapshot reader，但 opt-in status-line bridge 與符合資格之真實訂閱帳號驗證尚未完成。 |

ChatGPT.app 支援依賴未文件化的封裝細節：內附 Codex runtime 的路徑不是穩定的公開 contract。因此 ChatGPT 更新後，QuotaPulse 可能需要相容性調整。

## 安裝

### 下載建置版本

最初的 v0.1.0 GitHub Release 為 source-only，不會附上已核准的 QuotaPulse App、DMG 或安裝套件。

Developer ID 簽章、Hardened Runtime 驗證、notarization 與 binary distribution 檢查都刻意延後。自訂 Homebrew Tap 也只是可能的後續安裝方式，目前沒有官方 Homebrew Cask。

### 從原始碼建置

需求：

- macOS 14 以上
- 含 Swift 6 toolchain 與 macOS 14 SDK 以上版本的 Xcode；v0.1.0 已使用 Xcode 26.6 驗證
- 若要使用目前已驗證的 Codex 即時整合，需要安裝 ChatGPT.app；單純編譯與啟動 App 不需要

Clone 並開啟專案：

```sh
git clone https://github.com/YinCheng0106/QuotaPulse.git
cd QuotaPulse
open QuotaPulse.xcodeproj
```

在 Xcode 選擇 `QuotaPulse` scheme 與 **My Mac**，再選擇 **Product → Run**。如果 Xcode 要求設定本機開發用 team，請在 Signing & Capabilities 選擇自己的 team；這不代表已完成散布用的 Developer ID 簽章。

對應的命令列建置指令為：

```sh
xcodebuild \
  -project QuotaPulse.xcodeproj \
  -scheme QuotaPulse \
  -destination 'platform=macOS,arch=arm64' \
  -configuration Debug \
  build
```

## Codex 整合方式

QuotaPulse 會尋找相容的 Codex 執行檔，優先使用 ChatGPT.app 內附的 runtime，再 fallback 到支援的舊版或獨立安裝位置。它會直接啟動 `codex app-server`，並透過已有文件的 stdio protocol 呼叫 `account/rateLimits/read`。

驗證身分仍由 Codex 負責。QuotaPulse 不會讀取或複製 `~/.codex/auth.json`、擷取互動式 `/status` 畫面，也不會掃描 Codex session history。Provider 資料經過正規化後才會交給 SwiftUI。

## 通知

取得新鮮的 provider 資料，且剩餘額度至少為 20% 時，QuotaPulse 會透過 macOS `UserNotifications` 在本機排定重設提醒。短額度視窗可在 1 小時與 30 分鐘前提醒；長視窗則可在門檻未超過視窗長度時，於 24 小時、6 小時與 1 小時前提醒。你可以在「設定」中關閉全部通知或個別門檻。

QuotaPulse 也會在每次刷新後比對有上限的 normalized provider 狀態，判斷 quota window 是否真正進入新 cycle，並在該視窗完成重設時最多通知一次。單純 percentage 下降不計為 reset，persisted cycle identity 也會避免 App restart 後重複通知。官方外部 Reset Intelligence feed 仍是未來階段；詳見 [docs/RESET_INTELLIGENCE.md](docs/RESET_INTELLIGENCE.md)。

## 隱私

QuotaPulse 在本機處理用量資料，不需要 QuotaPulse 帳號、後端、分析服務或雲端同步。它的設計不會刻意上傳：

- prompt 或對話內容
- 原始碼或程式開發歷史
- 驗證憑證
- provider session 內容

使用 Codex 時，QuotaPulse 只會向本機安裝的 runtime 傳送取得 rate-limit 資料所需的 app-server protocol request；該 runtime 仍依原本設計處理 provider 通訊與驗證。使用 Claude Code 時，目前實作的 reader 只接受小型、有版本的 QuotaPulse 自有 snapshot，不會掃描 transcript、history、credential 或內部 usage cache。

以上描述的是 QuotaPulse 的實作邊界，不會改變 ChatGPT、Codex、Claude Code、macOS 或 Mac 上其他軟體本身的隱私與網路行為。

## 效能理念

QuotaPulse 優先採用事件驅動更新、保守的刷新週期、有上限的 process output，以及同一時間只進行一個合併後的刷新。倒數畫面本身不會觸發 provider request。

在開發機約一小時的測試中，QuotaPulse 閒置記憶體維持在約 48 MB；開啟選單或「設定」時曾短暫到約 70 MB，刷新時則短暫增加約 10–20 MB，之後都會往基準值回落。觀察到的閒置 CPU 接近 0%。這些是單一開發環境的觀察結果，不是所有環境的保證；量測條件與限制請參閱 [docs/PERFORMANCE.md](docs/PERFORMANCE.md)。

## Provider 相容性疑難排解

如果 provider 用量變成無法取得，請開啟**「設定」→「診斷」**並選擇**「複製診斷資訊」**，再把英文報告貼到 GitHub Issue。報告只包含 allowlist 允許的版本、系統、provider、runtime、連線、刷新與 metadata 可用狀態；不包含憑證、prompt、session、專案資料、私密路徑、原始 provider 回應或實際額度百分比。

請勿附上原始 app-server output、Codex session 檔、驗證檔案或範圍過大的系統 log。

## 已知限制

- 需要 macOS 14 以上
- 已在 Apple silicon 驗證；Intel Mac 尚未驗證
- ChatGPT.app Codex runtime 探索依賴未文件化的 bundle 路徑
- Claude Code 支援為 Experimental / Unverified
- 最初的 v0.1.0 為 source-only release；可下載 binary 的散布驗證尚未完成
- 沒有用量歷史與雲端同步
- 沒有 iPhone App
- 尚未實作官方外部 Reset Intelligence feed 擷取

## 路線圖

QuotaPulse 現已包含本機 reset-cycle detection。未來可能進行經審查的 Claude Code opt-in bridge、更廣泛的 provider 與硬體驗證、簽章與 notarization，以及保留來源連結的官方 Reset Intelligence feed 擷取；這些未來項目都不是目前已實作功能。詳情請參閱 [ROADMAP.md](ROADMAP.md)。

## 參與貢獻

歡迎範圍明確的貢獻。送出 pull request 前，請先閱讀 [CONTRIBUTING.md](CONTRIBUTING.md)、[SECURITY.md](SECURITY.md) 與 [ARCHITECTURE.md](ARCHITECTURE.md)。

## 授權

QuotaPulse 採用 [MIT License](LICENSE) 授權。
