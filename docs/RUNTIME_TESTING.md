# QuotaPulse v0.1 長時間 Runtime 驗證

本文件是 QuotaPulse v0.1 的人工 runtime 測試手冊。目標是找出長時間執行、反覆刷新、重連、Settings／menu lifecycle 與通知流程中的累積問題；不是用單元測試取代 soak test，也不是用單一記憶體讀數判定 memory leak。

效能門檻以 [`docs/PERFORMANCE.md`](PERFORMANCE.md) 為唯一來源。本文件負責測試步驟與紀錄格式。

## 1. 前置條件

- macOS 14 以上。
- Xcode 與 Command Line Tools 可正常使用。
- ChatGPT.app 可正常啟動，而且其整合 Codex runtime 已登入並可取得額度。
- 測試期間避免同時執行另一份 QuotaPulse。
- 每次 Xcode Run、command-line launch 或 Computer Use 前，先以 QuotaPulse 的正常 Quit 結束既有 Debug process，並確認沒有另一個相同 bundle host；不要用 `open -n` 或同時保留 Xcode Run 與 DerivedData launch。
- 測試前記錄 macOS、Xcode、ChatGPT.app 與 Codex runtime 版本；不得記錄 credential、token、provider raw response、prompt、conversation、session 或私密路徑。
- 先執行完整 XCTest；自動測試通過只代表既有不變量仍成立，不代表長時間穩定。

建議分成兩種執行：

1. **Release soak**：正式記憶體與 CPU 驗收，以 Activity Monitor、`ps`、`top`、`lsof` 與 Instruments 觀察。效能預算只套用在這一輪。
2. **Debug diagnostics run**：觀察 refresh、scheduler、Codex child、reader、notification 與 provider 狀態。Debug 記憶體不可拿來判定 Release 是否符合預算。

### 開發與正式 bundle identity

QuotaPulse 使用同一個 app target，透過 Xcode build configuration 隔離 macOS 以 bundle identifier 管理的狀態：

| Configuration | Bundle identifier | Display name |
| --- | --- | --- |
| Debug | `dev.quotapulse.development.app` | `QuotaPulse Debug` |
| Release | `dev.quotapulse.app` | `QuotaPulse` |

因此平常從 Xcode Run 啟動 Debug 時，`MenuBarExtra` 的 Control Center 可見性、`SMAppService.mainApp` 的 Launch at Login registration、`UserDefaults.standard` domain 與 `UNUserNotificationCenter.current()` 的權限／通知都屬於 Debug identity，不會沿用或寫入 Release identity。兩者不使用 shared preferences，也沒有 App Group entitlement；Debug 首次啟動看到預設設定是預期行為，不應從 Release preferences 手動搬移。

`QuotaPulse.app` 檔名與 `QuotaPulse` executable 刻意維持不變，讓 test host 與既有指令保持穩定；在 Finder、系統通知與相關 macOS 設定中，Debug 以 `QuotaPulse Debug` 顯示。要驗證 Release runtime 時，務必明確使用 Release 產物的完整路徑，不要把 Debug build 複製、改名或註冊成 production app。

App-hosted live tests 的 UserDefaults opt-in 也必須寫入 Debug domain：`runLiveNotificationTest` 與 `runLiveCodexProviderTest` 都使用 `dev.quotapulse.development.app`，測試後立即刪除。不要再把這些 development-only keys 寫入 `dev.quotapulse.app`。

一般 XCTest 也是 app-hosted，平行 suite 可能同時建立多個 `QuotaPulse.app` test processes。Test host 的 `MenuBarExtra` session insertion 固定為 `false`，所以它們不要求顯示 status item；binding callback 也不寫 persisted user intent。所有直接修改 `SettingsStore` 的 tests 必須繼續使用 UUID suite 並清除 domain。完整測試前後都應抽查 `presentation.menu-bar-extra.requested` 沒有改變；system-level Control Center 可見性不是普通 XCTest 的驗證項目。

若要做實際 Launch at Login register／restart 測試，先把已簽章 Debug artifact 安裝到獨立且穩定的 `/Applications/QuotaPulse Debug.app`，再從該路徑啟用；不要覆蓋 `/Applications/QuotaPulse.app`。用 `sfltool dumpbtm` 確認紀錄屬於 `dev.quotapulse.development.app`，測試完成後先在 QuotaPulse Debug 關閉登入時啟動，再移除測試 artifact。DerivedData 或 `/tmp` 啟動只適合確認 UI／identity，不足以宣稱 installed-app registration 與重新登入已通過。

## 2. 建置與啟動

### Xcode

在 Xcode 開啟 `QuotaPulse.xcodeproj`，選擇 `QuotaPulse` scheme 與 `My Mac`。

- Diagnostics run：使用 Debug，按 Run。
- Performance soak：Edit Scheme > Run > Build Configuration 改成 Release，再按 Run。

### Command line

以下命令把產物放在獨立的暫存 Derived Data，不會改寫 repository：

```sh
/usr/bin/xcodebuild \
  -project QuotaPulse.xcodeproj \
  -scheme QuotaPulse \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /tmp/QuotaPulseRuntime-Debug \
  build

/usr/bin/open /tmp/QuotaPulseRuntime-Debug/Build/Products/Debug/QuotaPulse.app
```

Release：

```sh
/usr/bin/xcodebuild \
  -project QuotaPulse.xcodeproj \
  -scheme QuotaPulse \
  -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /tmp/QuotaPulseRuntime-Release \
  build

/usr/bin/open /tmp/QuotaPulseRuntime-Release/Build/Products/Release/QuotaPulse.app
```

## 3. DEBUG runtime snapshots

Debug build 的 Settings > Development 有 `Log runtime snapshot`。它只在按下時查詢 pending notifications 與目前 process footprint，然後把一行 privacy-safe snapshot 寫到 Unified Logging。正常 refresh 開始與結束也各寫一行；沒有 timer、background sampler 或 in-memory history。

在 Terminal 監看：

```sh
/usr/bin/log stream \
  --style compact \
  --predicate 'subsystem == "dev.quotapulse.development.app" AND category == "RuntimeDiagnostics"'
```

主要欄位：

| 欄位 | 意義 | 健康值 |
| --- | --- | --- |
| `memory_bytes` | QuotaPulse process 的 `phys_footprint` | 看趨勢，不以單點判定；Release 預算仍以外部量測為準 |
| `app_refresh_active` / `app_refresh_max` | App-level refresh 數與本次 process 觀察到的最大值 | current 0 或 1；max 1 |
| `provider_refresh_active` / `provider_refresh_max` | 正在執行的 provider fetch 總數與最大值 | current 0 或 1；max 1 |
| `refresh_in_flight` | 是否有 App-level refresh | 閒置時 `false` |
| `last_attempt_epoch` | 最近一次 refresh attempt | 每次實際開始刷新才改變 |
| `last_success_epoch` | 最近一次至少一個 provider 成功的 refresh | 成功後更新；全失敗時不虛構成功 |
| `scheduler` / `refresh_scheduler_count` | 排程狀態與 sleeping scheduler 數 | 閒置通常 `scheduled` / 1；刷新中 0；sleep 時 `suspended_for_sleep` / 0 |
| `next_refresh_epoch` / `backoff_failures` | 下次 deadline 與目前 failure backoff 階段 | 正常約 15 分鐘；失敗依 1／2／5／15／30 分鐘 |
| `codex_state` / `codex_pids` / `codex_process_count` | QuotaPulse 擁有的 Codex connection 狀態與 child PID | 健康後 `healthy`、1 個 PID、count 1 |
| `codex_stdout_readers` / `codex_reconnects` | 目前 reader 數與 process 內累計 replacement 次數 | 健康時 reader 1；每次有效重連 reconnect 加 1 |
| `pending_notifications` | identifier 以 `quotapulse.` 開頭的 pending request 數 | 有界；測試通知重複排程仍最多一個相同 identifier |
| `notification_dedup_entries` | bounded reset-notification dedup entries | 0...32 |
| `providers` | 正規化 provider availability | 只有安全狀態，不含 raw error 或 payload |

`codex_pids` 是 QuotaPulse 自身啟動並觀察到的 child。若 child 被外部終止，snapshot 會在下一次 connection health check／refresh 後反映；外部 process table 仍是即時來源。

### 選擇性 SwiftUI invalidation tracing

只有在追查 Test E 時才啟用 Xcode scheme environment variable：

```text
QUOTAPULSE_DEBUG_LOG_SWIFTUI_CHANGES=1
```

它會對 `DashboardView` 與 `SettingsView` 使用 SwiftUI `_logChanges()`；macOS 14.0 會安全略過，14.1 以上才啟用。完成觀察後移除環境變數，避免大量 console noise。可在 Console.app 以 subsystem `com.apple.SwiftUI`、category `Changed Body Properties` 篩選。

## 4. 外部量測

取得目前 QuotaPulse PID：

```sh
QUOTAPULSE_PID=$(/usr/bin/pgrep -x QuotaPulse | /usr/bin/tail -n 1)
/bin/ps -p "$QUOTAPULSE_PID" -o pid=,%cpu=,rss=,etime=,state=,command=
```

`ps` 的 RSS 單位是 KiB。Activity Monitor 的 Memory／Real Memory 與 Debug snapshot 的 `phys_footprint` 定義不同；同一張結果表必須固定使用同一來源，不能混在同一欄比較。

短時間觀察 CPU、memory 與 thread count：

```sh
/usr/bin/top -l 5 -s 2 -pid "$QUOTAPULSE_PID" -stats pid,cpu,mem,threads
```

記錄 open-file 列數供趨勢比較：

```sh
/usr/sbin/lsof -n -P -p "$QUOTAPULSE_PID" | /usr/bin/wc -l
```

此數字包含不只 pipe 的 open-file records，因此只能在相同命令與相同測試條件下比較趨勢。若持續增加，再用完整 `lsof` output 與 Instruments 定位；回報時先移除私密路徑。

列出 QuotaPulse 的直接 Codex app-server child：

```sh
/bin/ps -axo pid=,ppid=,%cpu=,rss=,etime=,command= | \
  /usr/bin/awk -v parent="$QUOTAPULSE_PID" \
  '$2 == parent && $0 ~ /codex[[:space:]]+app-server/'
```

計數：

```sh
/bin/ps -axo ppid=,command= | \
  /usr/bin/awk -v parent="$QUOTAPULSE_PID" \
  '$1 == parent && $0 ~ /codex[[:space:]]+app-server/ { count += 1 } END { print count + 0 }'
```

不要用全系統的 `pgrep -f 'codex app-server'` 直接當 QuotaPulse child 數；ChatGPT、Codex 或其他開發工具也可能有自己的 app-server。

需要定位 retained allocations、Swift tasks、wakeups 或 view updates 時，依序使用 Instruments：

- Allocations 與 Leaks：找 refresh／reconnect／Settings cycle 後沒有回落的 retained objects。
- VM Tracker：區分 allocator／VM 波動與持續 footprint growth。
- Time Profiler：確認閒置時沒有持續工作。
- System Trace／Energy Log：確認 timer、wakeups、threads 與 process lifecycle。
- SwiftUI instrument：只在 UI lifecycle 測試中找 invalidation source；不要把 view body 次數單獨當 leak 證據。

## 5. Test A — Idle stability

1. 先做 Release run。冷啟動 QuotaPulse，打開 menu 一次，確認 Codex 顯示正常後關閉 menu。
2. 在 launch、10、30、60 分鐘記錄 Activity Monitor／`ps`／`top`、direct child count、child PID、thread 與 `lsof` 列數。
3. 發行前另做 8 小時 soak，至少一次 24 小時 soak。
4. 再做 Debug diagnostics run；在相同 checkpoint 打開 Settings，按 `Log runtime snapshot`，保存 snapshot line 後關閉 Settings。
5. checkpoint 之間不要持續打開 menu，也不要開啟 SwiftUI change logging。

預期：

- warm-up 可有波動，之後應接近 plateau；不能持續單調成長。
- Release idle CPU 接近 0%，正常穩態一般低於 1%。
- Codex 初始化前 child 可為 0；健康 connection 建立後恰好 1，PID 在正常刷新間保持不變。
- 閒置 snapshot 為 app/provider refresh 0、`refresh_in_flight=false`、scheduler `scheduled`、scheduler count 1、stdout reader 1。
- 不應有固定高頻 wakeup。

## 6. Test B — Repeated manual refresh

1. 記錄開始前的 QuotaPulse RAM、child PID/count、thread、`lsof` 與 Debug snapshot。
2. 約 20 次按下 menu 的 Refresh／Command-R。可在一輪仍進行時連續要求數次，再等按鈕恢復。
3. 每 5 次記錄一次 snapshot；第 20 次後等待 1 至 2 分鐘再量測 RAM、CPU、child、thread 與 open files。
4. 若用 Instruments，同時觀察 Swift tasks 與 allocations 是否在工作結束後回落。

預期：

- `app_refresh_max=1`、`provider_refresh_max=1`。
- healthy child PID 不變、process count 1、stdout reader 1。
- refresh 結束後 scheduler 回到 `scheduled` / 1；沒有第二個 loop。
- memory 可因 cache／allocator 上升，但應回到接近原 plateau，而不是每次刷新固定增加。

## 7. Test C — Provider failure and recovery

這個測試只暫停 QuotaPulse 自己的 child，不修改、搬動、覆寫或重新簽署 ChatGPT.app。

1. 用 direct-child 命令取得並再次確認 child 的 PPID 等於 `QUOTAPULSE_PID`，保存為 `QUOTAPULSE_CODEX_PID`。
2. 執行：

   ```sh
   /bin/kill -STOP "$QUOTAPULSE_CODEX_PID"
   ```

3. 立刻在 QuotaPulse 手動刷新。停止中的 app-server 應在約 5 秒 request timeout 後被 QuotaPulse 關閉；cleanup 必要時會使用 SIGKILL。
4. 記錄失敗 snapshot。預期 `backoff_failures=1`，scheduler deadline 約 1 分鐘後，舊 PID 不再存在：

   ```sh
   /bin/kill -0 "$QUOTAPULSE_CODEX_PID"
   ```

   預期回傳 `No such process`。若 PID 已被系統重用，必須重新核對 PPID 與 command，不可只相信 PID 數字。
5. 明確手動刷新以繞過等待中的 backoff，讓 QuotaPulse 建立 replacement。
6. 記錄新 snapshot 與 direct-child process table。

預期：

- 舊 child、pipes 與 reader 先停止，才出現 replacement。
- recovery 後恰好 1 個新 PID、stdout reader 1、`codex_state=healthy`、`codex_reconnects` 增加。
- 正常刷新恢復，failure count 回到 0，下一輪約 15 分鐘。
- error 與 log 不包含 provider raw output，也沒有隨重連累積的錯誤 history。

若測試步驟中途停止，對舊 PID 執行 `/bin/kill -CONT "$QUOTAPULSE_CODEX_PID"`；若 QuotaPulse 已完成 timeout cleanup，該 PID 應已不存在。

## 8. Test D — Active Codex usage

1. 保持 QuotaPulse 執行，同時正常使用 Codex 開發至少一個自動刷新週期。
2. 在 Codex 活動前、活動中、約 15 分鐘自動刷新後與 menu interaction refresh 後記錄 usage 顯示、timestamp、CPU、RAM、child PID/count 與 snapshot。
3. 關閉 menu 後再觀察 2 至 5 分鐘 idle CPU。

預期：

- usage 只在既有 refresh cadence／menu stale／manual refresh 更新。
- 倒數的 minute tick 不觸發 provider refresh。
- QuotaPulse child count 維持 1；其他工具自己的 app-server 不算入。
- menu 關閉後 CPU 回到接近 0%，memory 不持續成長。

## 9. Test E — Settings / UI lifecycle

1. 記錄 baseline snapshot、RAM、thread 與 open files。
2. 重複開關 Settings 50 次，重複開關 menu 200 次。
3. 在合理範圍切換 Codex／Claude enablement、notifications 與 reminder thresholds；每次等待 UI 完成，再觸發 refresh。
4. 測試 system sleep/wake 與 App activation 各數次。
5. 有 invalidation 疑慮時另開一次 Debug run，設定 `QUOTAPULSE_DEBUG_LOG_SWIFTUI_CHANGES=1`，只重現最小步驟並觀察 `DashboardView`／`SettingsView` change cause。
6. 結束後關閉 menu／Settings，等待 1 至 2 分鐘，再記錄 snapshot、RAM、thread、open files 與 Instruments object graph。

預期：

- App-lifetime `Runtime`、`AppModel`、`SettingsModel` 不因 scene 重開而重建。
- scheduler count 保持 1 或在 refresh／sleep 時暫為 0；不出現第二個 background loop。
- Codex enable/disable 不銷毀健康 connection；重新啟用只要求共用 refresh。
- observer、task、TimelineView、thread 與 open-file 趨勢回到固定範圍。
- minute countdown 只使含倒數的窄 view subtree 更新，不應改寫 `AppModel` 或要求 provider。

## 10. Test F — Notification lifecycle

1. 使用 Debug build；先記錄 snapshot 的 `pending_notifications` 與 `notification_dedup_entries`。
2. 在 Settings > Development 連續按 `Send test notification` 多次，再立刻按 `Log runtime snapshot`。
3. 測試通知使用固定 identifier，重複測試應替換同一 request，不應線性增加 pending count。
4. 反覆刷新與切換 notification／threshold settings，確認停用時只移除 QuotaPulse 自己的相符 pending requests。
5. Quit 並重新啟動 QuotaPulse，再次記錄 snapshot；若真實 usage 剛好符合 reset threshold，確認相同 logical reset generation 不重送。
6. XCTest 仍須覆蓋並行 evaluation、restart dedup、新 reset generation 與 32-entry 上限；人工測試不應製造或竄改真實 provider snapshot。

預期：

- `pending_notifications` 有界；重複 development notification 最多保留相同 identifier 的一筆 pending request。
- `notification_dedup_entries` 永遠不超過 32。
- notification policy 只隨既有 refresh／明確測試 action 執行，沒有自己的 timer 或 polling loop。
- 拒絕通知權限不影響 provider refresh、menu UI 或 scheduler。

## 11. 結果紀錄

每張表必須註明 build configuration 與數值來源。

| Time | Build | QuotaPulse RAM | CPU | app-server PID | app-server count | Active app refreshes | Active provider refreshes | Scheduler | Threads | Open-file rows | Notes |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | --- | ---: | ---: | --- |
| launch | Release | | | | | n/a | n/a | n/a | | | |
| 10m | Release | | | | | n/a | n/a | n/a | | | |
| 30m | Release | | | | | n/a | n/a | n/a | | | |
| 60m | Release | | | | | n/a | n/a | n/a | | | |

Debug diagnostics 另存 `runtime_snapshot` lines；不要把 Debug `memory_bytes` 與 Release RAM 放在同一趨勢線。

## 12. 健康行為與警訊

健康：

- warm-up 後 RAM、threads、open files、reader 與 retained allocations 接近 plateau。
- 每次 refresh／reconnect 的暫時尖峰會回落。
- healthy Codex connection 恰好 1 個 child、1 個 stdout reader。
- App/provider concurrent refresh 最大值都是 1。
- 一個 background scheduler；沒有 Foundation `Timer`，reset countdown 為 view-owned minute `TimelineView`。
- notification dedup state 最多 32 entries，沒有 notification history。

警訊：

- 每次 refresh、menu open、Settings open 或 reconnect 都固定增加 retained bytes、thread、FD、reader 或 task。
- warm-up 後 RAM 在數小時內維持正斜率，沒有 plateau；不要只因 allocator 單次擴張就宣告 leak。
- 同一 QuotaPulse PPID 下同時存在兩個 app-server，或 replacement 出現時舊 PID 尚未被清理。
- `app_refresh_max` 或 `provider_refresh_max` 大於 1。
- 閒置時 scheduler count 不是 1、CPU 長時間高於 1%，或有固定高頻 wakeup。
- pending notification／dedup entries 隨相同步驟無界增加。
- 關閉 menu／Settings 後 SwiftUI invalidation 仍持續，且可追到重複 model、observer 或 timer。

## 13. 回報疑似 memory／lifecycle regression

Issue 至少包含：

- 測試 A–F 的哪一個 scenario、完整重現步驟與迴圈次數。
- commit／工作樹識別、Debug 或 Release、macOS／Xcode／ChatGPT／Codex runtime 版本。
- measurement source 與 checkpoint table；RAM 必須註明 RSS、Activity Monitor Memory 或 `phys_footprint`。
- sanitized `runtime_snapshot` lines、QuotaPulse direct-child process table、thread 與 open-file trend。
- 最小化 Instruments trace 或 allocation／retain evidence；指出成長斜率與第一次偏離 plateau 的操作。
- expected 與 actual process/task/timer/notification count。
- Quit 後 child 是否仍存在。

不得附上 provider raw stdout/stderr、prompt、conversation、session、source code、credential、token、完整私密路徑或未清理的 `lsof` output。若證據只有單點 RAM 上升，先補做相同條件的時間序列與 refresh/reconnect 後回落觀察，再分類為 regression。
