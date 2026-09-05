# QuotaMew v0.1 效能與生命週期預算

本文件定義 QuotaMew v0.1 的初始工程預算、2026-08-26 至 2026-08-27 的生命週期稽核結果，以及 Release 長時間測試方式。預算數字是 acceptance targets；實測結果只代表其註明的單一開發環境與觀察期間。Debug build、單元測試、短暫 smoke run 或單一機器的一小時觀察都不能證明所有環境的長時間穩定。

## 稽核範圍

| 區域 | 已檢查的實際路徑 |
| --- | --- |
| ChatGPT／Codex runtime discovery | `CodexExecutableLocator.init`、`locate()`、`resolve(_:)`、`validatedExecutable(_:)`、`cachedSource` 與注入的 `applicationURLLookup` closure |
| Process／Pipe／FileHandle | `CodexAppServerClient.healthyConnection()`、`ManagedCodexConnection.write(_:)`、`requestStop()`、`stop()`；`ClaudeSnapshotReader.readSnapshot()`、`openSnapshot()` |
| stdout／stderr／JSON | `CodexStdoutReader.run`、`yieldResponse`、bounded `AsyncThrowingStream`；stderr 的 null-device routing；Codex DTO decoding 與 Claude 兩階段 bounded decoding |
| Tasks／refresh／reconnect | `CodexAppServerClient.readRateLimits()`、`awaitRequest(_:)`、`response(id:from:)`、`disconnect(_:)`；`RefreshCoordinator.refresh()`／`cancel()`；`UsageService.refresh()`；`AppModel` 的 App-owned refresh task、單一 scheduled task、backoff 與 sleep/wake rescheduling |
| Timers／callbacks／closures | `ResetCountdownView` 的 `TimelineView`；`DashboardView` 的同步 menu/manual triggers；`ContinuousRefreshSleeper`；`AppModel` lifecycle closures；`CodexConnectionLifecycle` termination closure；refresh 完成後的 notification evaluation |
| Caches／snapshots／service lifetime | `CodexExecutableLocator.cachedSource`、`AppModel.providerStates`、`ProviderUsageSnapshot`、`ClaudeSnapshotReader`；`AppDependencies` → `UsageService` → providers 的 App-lifetime ownership；`NotificationService` 的單一 authorization task reference 與最多 32 筆 `UserDefaults` dedup entries |
| Continuations／observers | Production target 沒有 `CheckedContinuation`；`AppModel` 透過一個 observer bag 監看 App activation／termination 與 system sleep／wake，`CodexConnectionLifecycle` 另有 process cleanup termination observer。兩者都使用 weak capture 並於 owner 釋放時移除；`NotificationService` 沒有註冊 observer、sleeping Task 或 timer |

## 預算

| 指標 | v0.1 目標 |
| --- | --- |
| QuotaMew idle RAM | 實務上低於 70 MB；stretch target 低於 50 MB。須另外記錄 app-server child 與 App + child 合計 footprint |
| Idle CPU | 接近 0%，正常穩態低於 1%；沒有刷新、畫面更新或通知工作時不應持續喚醒 |
| 記憶體趨勢 | warm-up 後不可持續單調成長；8 小時或 100 次刷新後，QuotaMew RSS 漂移應低於 10 MB，超出即調查 |
| Codex app-server children | 尚未建立 connection 時 0；健康連線期間恰好 1；重連與 shutdown 後舊 child 為 0 |
| Concurrent provider refreshes | 全 App 最多 1；providers 依序刷新 |
| Codex stdout readers | 每個健康 connection 恰好 1；replacement 啟動前舊 reader 必須結束 |
| Codex stderr readers | 0；stderr 直接導向 null device，不在記憶體保留 provider output |
| Automatic refresh cadence | 正常約 15 分鐘；全 App 只有一個具 30 秒 tolerance 的 sleeping task。可重試失敗依 1／2／5／15／30 分鐘退避，連續失敗上限 30 分鐘 |
| Menu stale threshold | snapshot 與上次讀取完成均超過約 3 分鐘才在 menu open 時要求背景刷新，且遵守失敗退避期限；UI 先顯示 cached snapshot，不等待 provider |
| In-memory history | 0 筆歷史序列；只保留每個 provider 的目前 `ProviderState`／snapshot |
| Notification state | 每個 provider/window 只保留目前 reset generation，全域最多 32 筆小型 `UserDefaults` entries，encoded input 上限 64 KiB；不保存 notification body、percentage 或 snapshot |
| Provider input bounds | Codex 每行 stdout 1 MiB、response channel 1 筆；Claude snapshot 16 KiB；locator cache 1 個 source |

## 2026-08-27 開發機實測觀察

以下結果來自同一部開發機約一小時的連續實際執行。原始觀察沒有記錄 build configuration、記憶體量測工具、app-server child 的獨立 footprint、thread count 或 file-descriptor count，因此數字只作為這次 v0.1 稽核的實機證據，不應外推成通用保證。

| 區域 | 設計目標 | 本次觀察結果 | 判讀與限制 |
| --- | --- | --- | --- |
| Idle memory | 實務上低於 70 MB；stretch target 低於 50 MB | QuotaMew 約 48 MB，約一小時內大致穩定，沒有觀察到持續或單調成長 | 在這部機器與本次量測方式下達到 stretch target。這不等同證明不存在 memory leak，仍須做 8／24 小時 Release soak 與 retained-allocation／FD 趨勢檢查 |
| Menu／Settings memory | 關閉 UI 後應回到接近 warm baseline，不應每次開啟固定累積 | 開啟 menu 或 Settings 時可短暫到約 70 MB，約 0.5–1 秒回到接近 48 MB | 回落速度與沒有累積趨勢，符合 Swift／SwiftUI view 建立、layout、allocator cache 等短暫配置行為；目前沒有 retained-object 證據，不針對此尖峰最佳化 |
| Refresh memory | 工作完成後應回到接近既有 plateau | 手動／provider refresh 約暫增 10–20 MB，之後回落；多次刷新沒有 progressive growth | 符合 bounded JSON decoding、snapshot replacement 與 process I/O 的短暫配置；尚未以 100 次 refresh 或 Allocations instrument 量測 retained bytes |
| Idle CPU | 接近 0%，穩態低於 1% | 正常背景執行時實際觀察為接近 0%，沒有持續背景活動 | 與單一 15 分鐘 sleeping scheduler、可見 UI 的 minute-level `TimelineView` 及無 notification polling loop 的設計一致；本輪沒有保存 wakeup／Energy Log trace |
| Codex failure path | child 失敗後安全呈現 unavailable／failure，後續可恢復且 child／reader 有界 | 測試期間刻意終止 Codex runtime／app-server，QuotaMew 維持可用並顯示預期 provider failure state | 實機觀察確認 UI／error path；舊 PID、reader task、pipe 與 FD 的逐項清理結論仍來自目前 source path 與自動測試，不把這次觀察描述成完整 reconnect resource trace |

整體而言，本次短時間的 allocation 尖峰都有快速回落，且一小時內沒有 progressive memory growth 或持續 idle CPU。這些現象與目前 bounded lifecycle 設計相容，沒有證據支持把 menu／Settings 或 refresh 尖峰視為 leak。

## DEBUG runtime diagnostics 邊界

`RuntimeDiagnostics`、Settings 的 `Log runtime snapshot`／feedback、Codex PID／reader tracking，以及選擇性的 SwiftUI `_logChanges()` 全部以 `#if DEBUG` 編譯。Release 不包含這些型別、按鈕、log strings 或狀態更新；Release soak 只能使用 Activity Monitor、`ps`、`top`、`lsof` 與 Instruments 量測。

Debug 診斷沒有 timer、background sampler、analytics、database 或 append-only history。它只保留目前 scalar／active-set 狀態與 observed maximum concurrency；正常 refresh 開始／完成及使用者按下 snapshot 時才寫一行 privacy-safe Unified Log。Pending notification count 只在手動 snapshot 時按需查詢。完整欄位、命令、Tests A–F 與回報格式見 [`docs/RUNTIME_TESTING.md`](RUNTIME_TESTING.md)。

## 已驗證的不變量

| 不變量 | 實作與證據 | 結論 |
| --- | --- | --- |
| 最多一個 Codex child | `CodexAppServerClient.readRateLimits()` 以 actor-owned `inFlightRequest` 合併讀取；`CodexConnectionLifecycle` 只持有一個 connection | 自動測試已驗證並行讀取共用一個 request/process |
| 健康時重用 app-server | `healthyConnection()` 先重用 `isHealthy` connection | 自動測試已驗證連續回應來自同一 process state |
| 重連乾淨替換 | `disconnect(_:)` 與 `healthyConnection()` 在建立 replacement 前先 `await connection.stop()` | 自動測試已驗證舊 PID 已不存在後才成功建立第二個 process；本次實機 kill 測試另確認 failure state 不會破壞 App 功能，但沒有逐項記錄 PID／FD／reader 數 |
| 失敗 child 終止並 reap | `ManagedCodexConnection.requestStop()` 關閉 handles、送出 terminate、必要時 SIGKILL；若 Foundation 尚未觀察到結束，再呼叫 `waitUntilExit()` | timeout、失敗重連與 shutdown tests 已通過 |
| reader tasks 不重複 | 每個 connection 只建立一個 `stdoutTask`；`stop()` 等待該 task 完成後才返回 | 重連路徑由測試間接覆蓋；仍須用 Instruments 長時間確認 task 數不成長 |
| continuation 不累積 | Production code 不使用 `CheckedContinuation`；response 等待使用 bounded `AsyncThrowingStream`，stop 時明確 finish | 靜態稽核通過 |
| timer 不累積 | 沒有 Foundation `Timer` 或全域 tick；`AppModel` 最多一個 scheduled refresh task；`ResetCountdownView` 只有 view-owned、每分鐘一次的 `TimelineView`；notification policy 只隨 refresh 評估，1 秒 local-notification trigger 由系統持有且不重複 | 自動測試已驗證 200 次 menu open、重複 activation 與 sleep/wake 後仍只有一個 refresh schedule；notification tests 已驗證重複、並行與手動評估不重送，仍應以 Instruments 長時間確認 |
| refresh 不重疊 | `AppModel` 的手動、自動、menu 與 lifecycle triggers 共用唯一 refresh task；`RefreshCoordinator.refresh()` 再共用唯一 service task；`UsageService.refresh()` 依序走訪 providers | 自動測試已驗證 manual/manual、manual/automatic 與 scheduled refresh 不重疊 |
| failure backoff 有上限 | 只有 `.failed` 進入 1／2／5／15／30 分鐘退避，成功或非暫時 unavailable 會回到 15 分鐘；menu open 不繞過退避，手動刷新可立即重試 | 自動測試已驗證進階、30 分鐘上限、menu gate、其他 provider 持續可用與 recovery reset |
| sleep/wake 不重複排程 | sleep 取消 sleeping task但保留 deadline；wake／activation 只在沒有 refresh 與 schedule 時恢復 | 自動測試已驗證重複 wake／activation 後只有一輪 refresh 與一個 schedule |
| snapshot 與 JSON bounded | `AppModel` 只替換目前 states；Codex line 1 MiB、channel 1 筆；Claude 一次最多讀 16 KiB | 靜態稽核通過 |
| 無 usage history | Domain、services 與 providers 都沒有 append-only usage collection；唯一新增的 persistence 是 bounded notification identity／threshold metadata | 靜態稽核與 32-entry bound test 通過 |
| handles／pipes 在 replacement 後釋放 | `requestStop()` 明確關閉 stdin/stdout handles，reap process；舊 connection 與 `Pipe` owners 隨 replacement stack 釋放 | shutdown/reconnect process tests 已通過；長時間仍須追蹤 FD count |

## 稽核發現與處置

### 已修正

| 分類 | 嚴重度 | 位置 | 失敗或成長情境 | 處置 |
| --- | --- | --- | --- | --- |
| Confirmed | Medium | `CodexAppServerClient.readRateLimits()`（舊實作） | 每次刷新都建立新的 `Process`、`Pipe` 與 async reader。即使沒有永久 leak，長時間刷新會持續製造 process／allocation churn，而且不符合健康 child 重用要求 | 改為 actor-owned 單一健康 connection，並合併重疊讀取 |
| High-confidence | High | 舊 `ManagedCodexProcess.terminateLocked()` | 舊 cleanup 關閉 handles 並送出 terminate，但沒有確認 child exit/reap，也沒有明確等待 reader task 結束。慢速或不合作 child 可能讓舊 process/task 與 replacement 短暫共存 | `ManagedCodexConnection.requestStop()` 使用 bounded terminate grace、必要時 SIGKILL，並在仍為 running 時 `waitUntilExit()`；`stop()` 再等待 stdout task |
| High-confidence | High | 長駐 connection 的 App 結束路徑 | 健康 child 若只靠 ARC，在 macOS App 終止時不保證有機會執行非同步 cleanup，可能留下 orphan child | `CodexConnectionLifecycle` 註冊一個 `NSApplication.willTerminateNotification` observer，同步 request stop；closure 弱參照 owner，deinit 會移除 observer |

### 保留風險，未做大型重構

| 分類 | 嚴重度 | 位置 | 情境與目前界線 | 決策 |
| --- | --- | --- | --- | --- |
| Theoretical | Medium | `RefreshCoordinator.refresh()`／`cancel()` | 任意未遵守 cancellation、永不返回的未來 provider 會讓唯一 `refreshTask` 長時間保留，後續要求也都等待它。現有 Codex 有 5 秒 timeout，Claude 是 16 KiB bounded local read，沒有可重現的 production hang | Defer；新增 provider 時必須自帶 timeout/cancellation tests |
| Theoretical | Low | `AppModel` 的 App-owned scheduled task | Task 預期與 App 同生命週期，sleep、manual refresh、wake reschedule 與 termination 都會取消舊 handle；若底層 clock cancellation 行為改變，舊 sleeping task 可能短暫存活 | 自動測試以可控 sleeper 驗證 cancellation；長時間 menu／sleep-wake 測試仍觀察 task 數 |
| Theoretical | Low | `ResetCountdownView` 的 `TimelineView(.periodic(..., by: 60))` | 每個目前顯示的 reset window 有一個 SwiftUI-managed minute schedule。若 SwiftUI teardown 異常，反覆替換 rows 才可能累積喚醒 | 不做 refactor；以 Instruments 驗證，避免改成全域 timer |
| Theoretical | Low | `CodexExecutableLocator.cachedSource` | Cache 只有一個 enum source，使用前會重新驗證；健康長駐 child 期間不會重新 discovery，因此 App bundle 更新要等 connection 失效或 App 重啟才採用新 runtime | Accept；沒有成長路徑，重連時會重新驗證 |
| Theoretical | Low | lifecycle observers | `AppModel` observer bag 或 `CodexConnectionLifecycle` observer 若強捕獲 owner 或未移除會造成 retain cycle | 兩者都使用 weak capture 與 deinit removal 防護；長時間物件圖再確認 |

## 長時間 runtime 測試

必須用 Release build、真實 ChatGPT-integrated Codex runtime，並把 QuotaMew 與 app-server child 分開記錄。至少執行下列矩陣：

1. 在 launch、10、30、60 分鐘建立 checkpoint，之後繼續做 8 小時；發行前至少做一次 24 小時 soak。
2. 在健康 connection 上執行 1、10、100 次手動刷新，確認 PID 不變、child 數為 1、request 不重疊。
3. 在 refresh 中終止 child、模擬 timeout／離線並恢復，至少做 25 次 reconnect；每次確認舊 PID 消失後才出現 replacement。
4. 反覆開關 menu 200 次並切換 Settings，觀察 `TimelineView`、Swift tasks、threads 與 allocations 是否回到穩態。
5. Quit App 後確認沒有以 QuotaMew 為來源的 app-server child、open pipe 或 zombie process。

每個 checkpoint 記錄：QuotaMew RSS／physical footprint、child RSS、合計 footprint、CPU、thread count、open file descriptor count、app-server PID/count、Swift task 與 allocation 趨勢。使用 Activity Monitor 做基線，Instruments 的 Allocations、Leaks、VM Tracker、Time Profiler 與 System Trace 做成長來源定位。

驗收重點不是單一最低讀數，而是 warm-up 後沒有持續斜率：RSS、FD、threads、reader tasks 與 child count 應在刷新或重連後回到固定範圍。任何每次 refresh 都固定增加的 retained bytes、FD 或 task，即使尚未超過 70 MB，也視為 v0.1 blocker。
