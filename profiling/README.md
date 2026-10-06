# Tyrantlator profiling, phase 1

This extends the existing PC dashboard and ADB collector. It reuses Bannerlator's shared `FpsCounter`; CPU, memory, thermal, GPU-busy, named Wine/graphics workers and the optional FEX JIT probe keep their existing collection methods. No second dashboard or replacement collector is required.

## Enable one game

1. Use a custom APK built from the `profiling` branch. Preserve app data and signing identity before installing a build. This feature does not require uninstalling your existing app.
2. In the game's shortcut environment variables, add `TYRANTLATOR_PROFILE=1`. A shortcut value overrides the container value; use `0` to disable it for a game. Relaunch after changing it.
3. Enable the existing performance HUD / Show FPS. This phase follows that HUD's bound window and master toggle. If it is disabled, idle or unbound, the export is marked idle.
4. Open the game and run the existing `live.cmd` on your PC. The new **Tyrantlator app frame source** panel should show the shortcut name, container ID, display backend, HUD FPS, rolling p95 and latest 120 present intervals.

The existing installed app still works with the dashboard; it simply has no app export. CSV captures gain `app_profile_session`, `app_profile_game`, `app_hud_fps`, `app_hud_p95_ms` and `app_profile_status` columns.

## Measurement and lifecycle

The exporter samples the existing app HUD counter once per second on a background worker. It copies at most 120 intervals under the counter lock, performs no file I/O on the render thread, and atomically replaces `Android/data/<package>/files/tyrantlator-profile.json`. It uses Android elapsed realtime for freshness; the PC compares it with `/proc/uptime` in the same ADB call. Exports older than five seconds, stopped sessions, foreign packages and old HUD frames do not show live metrics. No server or network listener is added. The snapshot contains the shortcut name, but no launch arguments, environment variables or account information.

Intervals inherit the HUD's millisecond clock and pause filtering. They describe app-observed game presents before native frame generation, rather than SurfaceFlinger updates, GPU execution or frames on glass. Rolling p95 covers the last 120 intervals, which overlap between samples. The HUD can bind a launcher window; check the exported session and game window before interpreting it. App metrics are separate from the automatically selected CPU process.

Exact total FEX/Box64, Wine/Proton, DXVK/VKD3D, Vulkan/Turnip and GPU execution milliseconds remain unavailable. Next phases should instrument native components with timestamped spans and an accessible GPU timer, then align their clocks. Do not add named-worker CPU or JIT work to frame intervals.

## Deep CPU scheduling capture

Run `deep-profile.cmd` in the existing PC workspace while playing a repeatable scene. It records 20 seconds through the existing Perfetto capture script, then adds a historical capture panel to the same dashboard. Use `deep-profile.cmd -GameProcess sekiro.exe -Seconds 30` for another game. The default target is `ACOrigins.exe`; it never launches or stops the game.

The panel shows the busiest game threads, CPU milliseconds and percent of capture wall time, runnable wait totals and p95/max completed wait episodes, and other processes competing for CPU. Trace data loss and unfinished waits are reported; unfinished wait records are excluded from wait measurements. A missing game or scheduler source is explicitly unavailable. Captures are labeled with their saved time and selected process, independent of current live measurements. Thread names indicate work but do not prove total FEX, Wine or graphics-layer overhead. Capture averages do not identify which individual frame was delayed.

Reanalyze an existing trace with PowerShell 7: `scripts/deep-profile.ps1 -RunDir <capture-folder> -GameProcess ACOrigins.exe`. JSON and thread CSV reports are saved beside the trace. The existing workspace uses `tools/perfetto/trace_processor_shell.exe`; a PC copy needs that Perfetto tool and the ADB path described below. This enhancement does not require a new Android APK.

## PC sources and checks

`pc/` contains the existing Windows dashboard and collector with this additive integration. In the current workspace, canonical files remain at `C:\Android-PC-Emulator\dashboard.html` and `scripts/`; do not maintain a second live instance. The fork copy versions those sources together with the Android change. Copy the `pc/` files into a workspace containing `platform-tools-latest-windows/platform-tools/adb.exe`; pass `-Serial <device>` if needed. Historical `PROFILING.md` refers to additional tools already installed in the original workspace.

Run `powershell -NoProfile -File pc/tests/app-profile.Tests.ps1` to verify freshness and identity rejection. Build APKs through **CI Build (artifacts only)** on this branch for all three flavors. On the phone, check enabling profiling populates the panel, disabling the HUD removes live readings, and exiting stops the session. Compare exporter-on and exporter-off runs in the same scene to assess overhead. No new logcat tag is required: local JSON is the diagnostic interface.

## Live dashboard learning tools

The PC dashboard includes live process-family CPU/RAM/state readings, expandable plain-language explanations, and a live comparison against an optional pinned baseline. The live averages update over the latest 30 seconds without a timed recording. Missing data is excluded and valid sample counts are shown. Shared app UID does not prove a game relationship; descendant relationships are based on parent IDs. Process start time protects CPU deltas against PID reuse. Historical scheduling traces remain optional. Additional checks: `node pc/tests/dashboard-learning.test.js` and `pwsh -NoProfile -File pc/tests/process-family.Tests.ps1`.

## Phone-wide live CPU candidates

The live collector now samples the top 15 processes sorted by CPU and displays them on the same dashboard. Half a core of sustained sampled CPU outside the confirmed game family, host/display/system and profiler labels produces a review candidate after five seconds. Relationship labels are deliberately conservative; no automatic termination occurs. Gaps and game changes reset alert history, and paused readings are labeled. The list does not include every service or prove performance impact. Restart the existing live collector and refresh the dashboard; no APK update is needed. Verify with `pwsh -NoProfile -File pc/tests/background-cpu.Tests.ps1`.

## Live game threads and CPU units

Whole-game and named-worker CPU now use busy cores and CPU ms/s, independent of compositor updates. One busy core equals 1,000 CPU ms/s. Worker coverage is reported; warmup is distinct from measured idle. The live thread table shows the busiest 20 readable game threads with observed states, last CPU and roles inferred from names. Start times protect TID reuse; state/core do not measure wait duration or affinity. CSVs include named DXVK worker CPU rates and thread counts. Check `powershell -NoProfile -ExecutionPolicy Bypass -File pc/tests/game-threads.Tests.ps1`. No new APK is needed.

## Live CPU queue wait
The thread collector now also reads /proc/<game>/task/<tid>/schedstat in one batched call. Per-thread deltas show runnable CPU queue wait and scheduled CPU runtime in milliseconds per second. Sleeping, disk, lock and GPU waits are excluded. Counters need two samples from the same thread start time; missing, reset and all-zero inactive sources remain unavailable. The dedicated live panel ranks the five most delayed readable threads, independently of the CPU-work top 20, and reports measured coverage alongside GPU load. Counters do not prove a thread is on the frame's critical path. GPU busy is still not an execution timer.
Validated with synthetic reset/reuse/disabled-counter tests, dashboard rendering tests and two real Android init-thread samples. Game-thread scheduler access and live-game bottleneck interpretation still need a running game; no exact driver/DXVK/Proton attribution is claimed.
