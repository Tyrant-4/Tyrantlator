# REDMAGIC PC profiling

## Tyrantlator fork integration (phase 1)

The same dashboard and ADB collector now optionally read `Android/data/<active package>/files/tyrantlator-profile.json` from a custom Tyrantlator build. Add `TYRANTLATOR_PROFILE=1` to one game's environment and enable its existing HUD / Show FPS, then relaunch. The new app-frame panel shows HUD presents separately from SurfaceFlinger updates. Existing installed builds continue working with this panel unavailable. Stale, stopped or foreign app exports never become live readings. See `work/bannerlator-custom/profiling/README.md` for the source, limits and test steps. Exact native layer and GPU execution timings remain future work.

## Current live dashboard

Double-click `live.cmd`. It opens a local, offline browser dashboard plus the collector window. The default run is one hour; `live.cmd -Seconds 7200` runs for two hours. `mirror-profile.cmd` remains the separate phone/game preview. The dashboard follows whichever Windows game is auto-selected in the container, or an explicit `-GameProcess GameName.exe` override. Confirm the selected process and backend indicators at the top before interpreting readings.

The browser shows the latest 60 compositor update intervals, the last 120 sampled p95/GPU-busy readings, per-core CPU load and frequency, process CPU work, memory, swap, temperatures, FEX JIT timing when the instrumented runtime is in use, and named DXVK/VKD3D/D3DVK/D8VK worker CPU rows when the phone exposes them. Its event history highlights >50 ms surface updates, sharp p95 regressions, JIT bursts, swap pressure, and CPU frequency-limit drops. Event details show what else was measured at the same time; coincidence does not prove a cause. The browser marks itself paused if no sample arrives for ten seconds. It reads only local `work/live-sessions/live-data.js`; the Stop/Resume controls use a session-protected loopback connection on this PC.

Every sample is written to `work/live-sessions/redmagic-<timestamp>.csv` with the selected game, backend indicators, timing, CPU/GPU/memory/thermal data, bottleneck clue, evidence, and suggested check. The browser keeps a short rolling view while the CSV preserves the whole session. With a custom `-LogDirectory`, CSV files go there but the browser's current-data file stays at the project default path; `-DashboardDataPath` can override that path for advanced use.

The bottleneck clue uses conservative thresholds: new FEX JIT compilation, low memory plus swap-in, an observed allowed CPU-frequency drop, high GPU busy, and/or multiple saturated CPU cores. A slow compositor update paired with a busy GPU or CPU is labeled as a coincidence to investigate. The graph is SurfaceFlinger timing, not actual game frame time; use the game's frame-time overlay if available to confirm a real gameplay hitch. GPU frequency, exact GPU execution time, and complete per-frame FEX/Wine/DXVK/VKD3D/Turnip timings are still unavailable from the installed app and phone permissions. Earlier Sekiro-specific examples below remain historical examples, not launcher requirements.

Installed in the existing C:\Android-PC-Emulator project. The live dashboard uses built-in Windows PowerShell and the existing authorized USB ADB connection. Other profiling scripts may require PowerShell 7.

Open your game, then double-click profile.cmd for a 30-second capture. This launcher targets the currently observed Sekiro container package com.tencent.ig. Keep playing a repeatable scene until recording finishes. Results are in work/profiling/<UTC timestamp>. The recorder does not install a phone APK, relaunch the game, change drivers, or enable verbose logging.

For another package or duration:

```powershell
pwsh -NoProfile -File scripts/profile-redmagic.ps1 -Action Capture -Package com.tencent.ig -Seconds 60
pwsh -NoProfile -File scripts/profile-redmagic.ps1 -Action Probe -Package com.tencent.ig
```

Open trace.pftrace in https://ui.perfetto.dev and inspect CPU scheduling, CPU frequency, process memory, and FrameTimeline. Check trace stats for data loss and ftrace errors before interpreting results. Requested sources are not proof that every track contains data. The trace is system-wide; use processes-before.txt and after.txt to identify game/Wine processes and their UID. App logs are currently suppressed globally on this phone; the tool leaves that setting unchanged.

## Measurement coverage

| Requested measurement | Current method and limit |
|---|---|
| Frame time | SurfaceFlinger FrameTimeline when emitted; presentation intervals can differ from guest render intervals. MangoHud frame logs would provide a complementary guest-side measurement. |
| Game/guest CPU work | Scheduler running time by process/thread. Separating translated guest work requires symbols/JIT mappings. |
| FEX/JIT activity | The optional `2508-jitprobe2-2` content pack records cumulative FEX JIT compilation wall time. The live screen shows the new compile time per sample and cumulative time for the active Sekiro PID. This does not measure total FEX emulation overhead. |
| Wine/Proton overhead | Requires symbolized native samples or explicit spans; scheduler time alone does not separate it. |
| VKD3D CPU activity | Requires symbolized samples or VKD3D instrumentation. |
| Vulkan/Turnip submission | Requires API/driver instrumentation; generic gfx markers are insufficient for attribution. |
| GPU execution | No GPU render-stage producer was advertised at setup; unavailable as exact execution time. |
| CPU frequencies | Perfetto frequency events and 1-second polling, subject to device support. |
| Per-core CPU utilization | Scheduler or /proc/stat deltas. For stat use user+nice+system+idle+iowait+irq+softirq+steal; exclude guest fields. Busy = total-idle-iowait. |
| GPU utilization/frequency | Raw gpubusy pairs saved; interpretation needs driver semantics. gpuclk access was denied. Perfetto GPU frequency requested, availability unverified. |
| Memory | Process stats, system available/free/swap, GPU memory source and before/after package meminfo. |
| Shader compilation | Needs timestamped runtime instrumentation/logs. A frame spike alone is not proof of compilation. |
| Context switches/scheduling | sched_switch and sched_waking in Perfetto. |

CPU and GPU timelines overlap. Do not add component timings into a fabricated frame-time total. Capturing adds overhead; compare like-for-like runs with the same game settings, power mode, cooling, and warm/cold shader-cache state. Do not clear caches between runs unless deliberately testing cold compilation.

Next instrumentation stage: identify the installed container's FEX, Wine, VKD3D and Turnip versions; check profileable/debuggable eligibility, available symbols, and runtime profiling support. An instrumented build may be required. No exact layer breakdown is claimed by this baseline recorder.

References: https://perfetto.dev/docs/getting-started/system-tracing and https://perfetto.dev/docs/getting-started/cpu-profiling and https://perfetto.dev/docs/data-sources/gpu

Live display: double-click live.cmd. It shows the available measurements and marks unavailable layer timings explicitly. Game process CPU is measured in ms per second across threads and includes guest/runtime work; it is not a per-frame guest CPU timing. Context-switch rates are from /proc status. GPU busy is a driver sample and may return 0/0, displayed as unavailable. The default run lasts one hour; pass `-Seconds 7200` for two hours.


## Additional tools installed (2026-09-28)

* Perfetto Trace Processor v58.2: `tools/perfetto/trace_processor_shell.exe`. Downloaded from the official Perfetto prebuilt manifest; SHA-256 verified as `adfa6bad3d72be3ba9b83fa2b17b69fa13b3ab1cad0f42e52b86188bd5f0f997`. Run `analyze-profile.cmd` to analyze the latest saved trace. Its report is `work/profiling/<run>/analysis.txt`.
* Android GPU Inspector 3.3.3 portable: `tools/agi/agi.exe`. Official Google release zip SHA-256 verified as `3fad329ede78ee3d8fb9947906b138afa851c851ad22b20fb47d5388e25500c2`. It has not been attached to the current app. AGI frame profiling requires a debuggable app and compatible GPU driver. The installed `com.tencent.ig` package is not debuggable (`run-as` rejects it). Do not enable Vulkan validation/debug layers on the active game without a controlled test.
* Android NDK Simpleperf was already installed at `sdk/ndk/28.2.13676358/simpleperf`. Device also has `/system/bin/simpleperf`. The two tested events (`cpu-cycles` and `cpu-clock`) were reported unsupported for the running game. Installing another copy does not change device profiling permissions.

The 10-second baseline trace has 455,033 scheduler slices and 15.123 aggregate CPU-seconds in the Sekiro process. This is workload across multiple cores, not milliseconds per frame. It has no GPU execution slices. Its 33 package-associated FrameTimeline transaction slices do not represent all game frames. `GPU Memory` is the only GPU counter track in that trace, so it does not establish GPU frequency or GPU execution time.

Needed for exact per-layer frame timing: a Bannerlator/Proton/FEX/VKD3D/Turnip build with explicit timestamped spans and a GPU timer source, plus a way to align those timestamps with the Perfetto capture. Separate native components inside the game process cannot be timed from process CPU totals. The existing installed package cannot be profiled with AGI frame capture as-is. Preserve app signing and user data before replacing it with any custom build.

Sources: https://perfetto.dev/docs/getting-started/command-line-analysis ; https://developer.android.com/agi/start ; https://developer.android.com/guide/topics/manifest/profileable-element ; https://developer.android.com/ndk/guides/simpleperf

For Sekiro, target D3D11 translation (usually DXVK), not VKD3D-Proton: the game's published PC requirement is DirectX 11, while VKD3D-Proton implements Direct3D 12. Verify the selected container backend before assigning a DXVK timing. Other DX12 games can use the VKD3D row.


Sekiro debug HUD enabled in its shortcut on 2026-09-28: DXVK_HUD=fps,frametimes,compiler,pipelines,submissions,gpuload. The game was relaunched and the DXVK HUD visibly appeared at the title screen; the saved game was not loaded automatically. Existing DXVK startup logs were already enabled and confirmed DXVK v3.1-gplasync, Adreno 840, Turnip Mesa 26.2.99, and a 9,664-shader cache. Wine and FEX verbose logs remain off because they slow gameplay and do not yield per-frame component timings. To watch the phone HUD on the PC, run mirror-profile.cmd (scrcpy 4.1, official SHA-256 5b12172b3264b2889f4583ee64752ce832e29bc8b1089dca81093459697165db). The mirror itself adds encoding and USB overhead, so close it for low-overhead benchmark runs.


## Live millisecond rows added (2026-09-28)

`live.cmd` is the single dashboard. It measures compositor update intervals, whole-game CPU milliseconds per compositor update, separate wineserver and winedevice CPU milliseconds per update, and CPU milliseconds per update for named DXVK shader, queue/submit, and other DXVK threads. It also measures named in-game Wine threads. These values use 100 Hz Android process/thread CPU counters, so short samples are quantized; 0.00 ms/update can mean no CPU tick was observed in that interval. Thread rows are subsets, not total runtime overhead. DXVK calls made on unnamed game threads, total FEX overhead, Turnip driver CPU, and actual GPU execution still require instrumented builds or accessible profiling facilities. SurfaceFlinger updates are not one-to-one with game frames on this setup: during a 60 FPS Sekiro gameplay scene, the compositor reported roughly 90 updates/s. Use the in-game DXVK HUD for game FPS and frame intervals. Whole-game CPU work in `ms/s` is an aggregate across threads and cores; do not compare it directly with the 16.7 ms wall-time frame budget. A verified gameplay sample showed about 3,700–3,900 ms CPU/s, 80–87% driver GPU busy, and about 2.5 GB game RSS. Shader compilation remained near zero in the sampled steady scene.

## FEX JIT timing component (2026-09-28)

The optional `FEXCore-2508-jitprobe2-2.wcp` component was installed through Bannerlator Contents and selected only for the Sekiro shortcut. It writes `Download/fex-jit.csv` on the phone with `pid,endCounter,totalCompileTicks,counterFrequency`. The PC can read this file over ADB. `live.cmd` matches the selected game's PID to the JIT samples and converts counter deltas to milliseconds of JIT compilation wall time; other games without the probe show this reading as unavailable. Multiple compiler threads may overlap, so this number is aggregate work and must not be added to the frame interval. No new compilation is displayed as 0.00 ms only when a fresh probe sample confirms it; otherwise the dashboard labels the sample stale. A verified run reached the Sekiro title screen with the DXVK HUD and showed about 1,894.5 ms cumulative JIT compilation after startup. The previous FEX setting was `FEX-2609+124-Nightly-72b2ff88a-unix-0`; restore that version in Sekiro shortcut Settings > Advanced to return to the original runtime. Other game shortcuts were not changed. The instrumented component is based on FEX 2508, so performance comparisons with the original 2609 runtime are not like-for-like.

The live dashboard also shows a scrolling surface-timing graph of the latest 60 compositor updates. Newer updates appear on the right. Each `#` reaches the millisecond level shown at the left, `^` marks an interval above 50 ms, and the dashed 16.7 ms line is the wall-time target for 60 FPS. This is a graph of compositor updates, not DXVK game frames; compare it with the DXVK HUD's game frame graph when investigating a hitch.

## Live bottleneck view and session history

Double-click `live.cmd` while a game is running, or start it first and let it wait for a game. The dashboard refreshes after each ADB sample and writes one CSV row per sample to `work/live-sessions/redmagic-YYYYMMDD-HHMMSS.csv`. The CSV preserves the evidence for later comparison: compositor median/p95 and >33/>50 ms update counts; game process CPU milliseconds per second; GPU busy and recent average; peak per-core CPU busy; FEX JIT compilation delta and cumulative time; game RSS, system available memory and swap page rates; CPU/GPU/skin sensor temperatures; allowed CPU frequency changes; context-switch rate; the current bottleneck clue and its suggested check. `live.cmd -TargetFps 60` uses a 60 FPS target line in the surface graph. Adjusting `-TargetFps` changes only the graph's reference line, not game settings or the diagnosis.

The bottleneck clue is a screening heuristic. A sustained driver GPU-busy average of at least 85% suggests GPU-side pressure when game FPS falls; two or more cores at 90% busy adds a mixed-pressure clue. A new FEX JIT compile burst of at least 10 ms suggests a possible hitch. Low available memory together with high swap-in activity suggests memory pressure. A fall of at least 12% in an observed allowed CPU frequency suggests a heat or power-policy change. These thresholds are starting points, not calibrated proof for the REDMAGIC. A low allowed frequency relative to `cpuinfo_max_freq` does not itself prove thermal throttling. The dashboard's current scene may have GPU pressure without a missed game frame.

The phone currently exposes no accessible per-frame GPU execution timestamp, GPU clock, or timestamped shader-compile events to this tool. The DXVK HUD on the phone shows actual game frame time, FPS, and a compiler indicator; the PC dashboard's SurfaceFlinger graph shows compositor update intervals, which are different. The named Wine/DXVK thread CPU rows are partial subsets of whole-game process CPU work. They do not isolate game/guest, FEX emulation, Wine/Proton, DXVK, Vulkan/Turnip or GPU execution milliseconds per game frame. FEX JIT milliseconds are summed compilation wall time across workers and may overlap each other and the frame. Do not add these rows to estimate a frame total.

For a defensible bottleneck check, stand in one repeatable scene, watch a spike in the DXVK game-frame graph, note the dashboard's clue and time, then change one factor such as resolution and repeat. A large frame-time improvement after reducing resolution supports a GPU-side cause; a cold-only FEX JIT burst supports code compilation; swap activity suggests memory pressure. Use `profile.cmd` to capture a Perfetto scheduling trace when a CPU-side clue appears. Compare runs with the same power mode and cooling, and account for the installed FEX 2508 JIT probe versus the original FEX 2609 runtime.

## Current live dashboard: any Windows game in the container

`live.cmd` now defaults to automatic game and container selection. It chooses the largest active Windows `.exe` process by resident memory, excluding common Wine helper processes, and selects an active XServer SurfaceView without hardcoding a package. The screen and CSV identify the selected process, package, and graphics backend indicators. If another `.exe` is chosen, start the launcher with `-GameProcess GameName.exe`; `-Package package.name` can narrow the surface selection. For example, `live.cmd -GameProcess ELDENRING.exe -Seconds 3600`. The process name may be truncated by Android; use the displayed process list or an exact visible name for an override. Automatic selection is a heuristic, so check the name at the top of the dashboard before interpreting its CPU and memory readings.

The dashboard collects the same phone-wide CPU, GPU-busy, memory, swap, frequency, temperature, and scheduling clues for DXVK, VKD3D-Proton/D3D12, D8VK, WineD3D, and other backends. It searches loaded-library names and named worker threads for DXVK, VKD3D, D3DVK, D8VK, and WineD3D *indicators*; these are hints rather than definitive proof of the active render path. When exposed, it shows separate named DXVK shader/submit/other CPU rows and a VKD3D/D3DVK or D8VK worker row. A missing named worker does not mean the backend did no work: most translation and driver code can run on ordinary game threads. The installed FEX JIT probe only contributes JIT timing for processes that use that instrumented FEX component. Other games can still use the core dashboard while that row is unavailable.

Earlier sections document the Sekiro/DXVK setup and example measurements; they are not required settings for the current launcher. Only that Sekiro shortcut currently has the DXVK game-frame HUD enabled. For other games, enable their own frame-time overlay or runtime logging if available. SurfaceFlinger update intervals and driver GPU-busy readings alone cannot provide exact game frame time or per-layer FEX/Wine/DXVK/VKD3D/Turnip/GPU execution milliseconds.

## Deeper CPU profiling

Run `deep-profile.cmd` while Assassin's Creed Origins is playing a repeatable scene. The default capture lasts 20 seconds and targets `ACOrigins.exe`. It adds a historical CPU scheduling panel to the existing dashboard with busy game threads, runnable CPU waits, and competing processes. Use `deep-profile.cmd -GameProcess sekiro.exe -Seconds 30` for another game. It does not change Vulkan settings or launch/stop games.

Reports are saved under `work/deep-profiles/`. A missing game, absent scheduler data, trace data loss, and unfinished waits are reported explicitly. Thread CPU measurements are parts of game CPU work, not separate FEX/Wine/graphics layer totals or per-frame GPU time. No new APK is required.

## Live learning and comparison tools

The dashboard now includes a live game process family table: process/parent IDs, observed state, CPU core equivalents and resident memory. Parent ancestry identifies game descendants; processes that only share the game's Android UID are explicitly unconfirmed and can include other containers. CPU deltas require the same process start time, and exited leaders can still show measured CPU from remaining threads. No processes are stopped automatically.

Expandable explanations describe frame timing, CPU/GPU activity, memory, thread states and heat. The live comparison continuously averages the latest 30 seconds of fresh collector readings. “Pin current baseline” holds a reference while live values continue updating; there is no timed recording workflow. Restart or frame-session changes reset the live averaging window. Missing measurements are excluded and counted; averaged rolling p95 readings are not a run-wide percentile. The baseline is stored locally when browser storage is available and can be exported. Historical deep CPU captures remain optional.

## Live background CPU panel

The collector samples the phone's 15 busiest processes, explicitly sorted by CPU, alongside the existing readings. The dashboard labels the selected game, observed descendants, emulator host, Android display/system components and profiler transport. Everything else retains an unconfirmed relationship. Half a busy core across consecutive readings spanning five seconds generates a review candidate; no process is stopped automatically. Sampling gaps and game changes reset candidate history. The top-15 list is not an inventory of every service, and sampled CPU activity does not prove a frame-time cause. Main-thread exit does not hide remaining thread CPU. The collector's extra process sampler adds overhead; compare in the same scene if collection itself changes performance.

Run the updated `live.cmd` and refresh the dashboard. No new APK is required. Parser checks: `pwsh -NoProfile -File tests/background-cpu.Tests.ps1`.

## Live CPU units and game threads

The current dashboard displays whole-game and named-worker CPU as busy-core equivalents and CPU milliseconds per second, independent of compositor update counts. 1.00 busy core equals 1,000 CPU ms/s. Older sections' CPU/update descriptions are historical; the legacy game_cpu_ms_per_update snapshot field is retained only for compatibility. Named worker totals include only threads with valid deltas and report coverage; missing or new threads are not silently counted as idle. Shared-app Wine helper rates reuse the process-family sampler and do not prove a helper belongs to this game.

The live game-thread table reads all accessible selected-process thread counters and displays up to 20 sorted by CPU. It includes TID/name, inferred role, CPU %, CPU ms/s, busy cores, observed state and last processor. Start times protect deltas against reused TIDs. State/core are momentary observations, not wait durations or affinity. Thread totals and valid-delta counts are shown. Roles are suggestions from names rather than instrumented stage attribution. Sleeping can be normal; short CPU samples can slightly exceed 100% due to tick quantization. Exact per-frame layer and GPU timings remain unavailable.

Additional check: `powershell -NoProfile -ExecutionPolicy Bypass -File tests/game-threads.Tests.ps1`. No APK update is required.

## Live CPU queue wait
The thread collector now also reads /proc/<game>/task/<tid>/schedstat in one batched call. Per-thread deltas show runnable CPU queue wait and scheduled CPU runtime in milliseconds per second. Sleeping, disk, lock and GPU waits are excluded. Counters need two samples from the same thread start time; missing, reset and all-zero inactive sources remain unavailable. The dedicated live panel ranks the five most delayed readable threads, independently of the CPU-work top 20, and reports measured coverage alongside GPU load. Counters do not prove a thread is on the frame's critical path. GPU busy is still not an execution timer.
Validated with synthetic reset/reuse/disabled-counter tests, dashboard rendering tests and two real Android init-thread samples. Game-thread scheduler access and live-game bottleneck interpretation still need a running game; no exact driver/DXVK/Proton attribution is claimed.

## Live thread activity history
The dashboard keeps a rolling 60-second history of sampled CPU work and runnable CPU queue wait, up to 24 ranked thread tracks. Hover for timestamps and values. Missing samples and gaps remain gray. Each series includes thread start time to avoid merging reused TIDs. Game/collector session changes reset history; duplicate, old and out-of-order samples are rejected. Stopped collectors are labeled paused. This is continuous in-memory history, not an exact scheduler trace or per-frame stage timing. The collector exports up to 512 readable threads and reports whether that cap truncates coverage. No additional ADB polling is introduced.

## Live DXVK graphics activity
Command-stream (dxvk-cs), submission/queue and shader worker groups now export CPU ms/s, runnable CPU queue ms/s, workers with positive CPU deltas, and separate CPU/queue coverage. The dashboard aligns those samples with HUD present p95, FPS and driver GPU busy in a continuous rolling history. The grouped rates use all readable worker threads, including those outside the busiest 20. Zero measured shader activity is distinct from unavailable/warming-up counters; positive activity is not a compilation count. Roles remain inferred from thread names.
Installed DXVK 3.1 D3D11 binary contains drawcalls, submissions, pipelines, compiler and dxvk-cs markers. These are documented HUD features (https://github.com/doitsujin/dxvk#hud); the existing PC exporter does not expose native counters. Native draw/dispatch/pipeline counts and compilation backlog require a separate DXVK telemetry export. No driver, DLL, shader-cache, HUD setting or game launch changes were made for this PC-side panel. No GPU execution timing is inferred from submission-worker CPU work.

## Collector isolation
Only one live collector can run for a phone in a Windows session. Reopening `live.cmd` opens the dashboard and reports that monitoring is already running instead of adding duplicate phone polling. Stop the existing collector before changing its options. The lock is released automatically on exit, including forced process termination.

Scheduler-counter polling is opt-in: run `live.cmd -EnableSchedulerStats` to collect runnable queue wait. The default keeps CPU work and graphics-worker activity live without scheduler reads. Missing queue values with that option off are expected. Keep `TYRANTLATOR_PROFILE=1` and Show HUD enabled for app frame readings.

A steady Origins comparison on 2026-10-06 measured average app HUD FPS of 37.52 with scheduler polling off, 37.67 on, and 37.67 off again. That short test did not reproduce the reported slowdown and does not prove zero overhead or identify the earlier cause. Two simultaneous PC collectors were found and reduced to one before the comparison.
## Stop live monitoring
The dashboard button toggles between **Stop monitoring** and **Resume monitoring**. Stop suspends all phone polling and freezes the last readings. The game and Android Tyrantlator exporter continue. A small PC control listener stays idle so Resume can restore the same options, including scheduler readings. Measurement windows and chart sessions restart on resume; stopped time is excluded from rate calculations. Refresh the dashboard after updating these files. The button is disabled when the collector controls are unavailable. While stopped, a local heartbeat keeps Resume available without collecting phone data.

Controls bind only to 127.0.0.1 on an automatically assigned port and require a POST with the current collector's random session token. The collector checks requests between phone samples; stopping can take a few seconds. Exiting the collector window completely still requires reopening `live.cmd`; the dashboard cannot restart an exited control listener. It does not terminate Android processes, change shortcuts or alter graphics settings. Checks: `powershell -NoProfile -ExecutionPolicy Bypass -File tests/monitor-control.Tests.ps1` and `node tests/monitor-control.test.js`.
## Finished live dashboard layout
Overview leads with app HUD FPS and app present p95, followed by GPU busy, game CPU, RAM and separately labeled compositor p95. Focused Frames, CPU & Threads, Graphics, Processes and Compare tabs retain the existing readings. Historical captures have their own optional Captures tab. Navigation supports Left/Right, Home/End and keyboard focus; the chosen view is remembered locally. Resizing or changing views redraws charts.

Stop/Resume stays in the header. Stopped process, graphics and scheduler panels immediately label their readings frozen. Stopped updates cannot extend thread/graphics histories or pin a live baseline; a resumed collector starts a fresh comparison window. Missing readings show a dash; disabled scheduler polling is distinguished from warming-up counters. GPU execution timings and shader event counts remain unexported.

The redesign adds no phone queries and requires no APK update. Refresh dashboard.html to load the layout. Tests: node tests/dashboard-product.test.js, node tests/dashboard-tabs.test.js, node tests/dashboard-state.test.js and the existing monitoring/comparison/history regression tests. Browser visual inspection was unavailable because the connected browser tool disallows local-file navigation; DOM rendering and behavior were verified locally.