# Requires PowerShell 7. Uses the existing project's ADB; does not launch or stop apps.
param(
 [ValidateSet('Probe','Capture')][string]$Action='Probe',
 [ValidateRange(3,120)][int]$Seconds=30,
 [ValidatePattern('^[A-Za-z0-9_.]+$')][string]$Package='com.ludashi.benchmark',
 [ValidatePattern('^[A-Za-z0-9]+$')][string]$Serial='9126023101C5',
 [string]$ProjectRoot=(Split-Path $PSScriptRoot -Parent),
 [string]$OutputRoot=''
)
$ErrorActionPreference='Stop'
$adb=Join-Path $ProjectRoot 'platform-tools-latest-windows/platform-tools/adb.exe'
if(!$OutputRoot){$OutputRoot=Join-Path $ProjectRoot 'work/profiling'}
$id=[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss',[Globalization.CultureInfo]::InvariantCulture)+'-'+[guid]::NewGuid().ToString('N').Substring(0,6)
$out=Join-Path $OutputRoot $id
New-Item -ItemType Directory -Force $out | Out-Null
function Adb([string[]]$Argv){
 $r=& $adb -s $Serial @Argv 2>&1
 if($LASTEXITCODE){throw "ADB failed ($LASTEXITCODE): $($r -join "`n")"}
 return $r
}
Adb @('get-state') | Out-Null
Adb @('shell','getprop ro.product.model; getprop ro.build.version.release; getprop ro.build.type; getprop log.tag; cat /proc/uptime') | Set-Content "$out/device.txt"
Adb @('shell','perfetto --query') | Set-Content "$out/perfetto-sources.txt"
Adb @('shell',"dumpsys package $Package") | Set-Content "$out/package.txt"
Adb @('shell','ps -A -o USER,PID,PPID,NAME; dumpsys window | grep mCurrentFocus; true') | Set-Content "$out/processes-before.txt"
Adb @('shell','for p in /sys/class/kgsl/kgsl-3d0/gpubusy /sys/class/kgsl/kgsl-3d0/gpuclk /sys/class/kgsl/kgsl-3d0/devfreq/cur_freq /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq; do echo "$p"; cat "$p" 2>&1; done; true') | Set-Content "$out/capabilities.txt"
if($Action -eq 'Probe'){Write-Host "Probe saved: $out"; return}
$ms=$Seconds*1000
$config=@"
buffers { size_kb: 65536 fill_policy: RING_BUFFER }
duration_ms: $ms
data_sources { config { name: "linux.ftrace" ftrace_config {
 ftrace_events: "sched/sched_switch"
 ftrace_events: "sched/sched_waking"
 ftrace_events: "sched/sched_process_exit"
 ftrace_events: "power/cpu_frequency"
 ftrace_events: "power/cpu_idle"
 ftrace_events: "power/gpu_frequency"
 ftrace_events: "vmscan/mm_vmscan_direct_reclaim_begin"
 ftrace_events: "vmscan/mm_vmscan_direct_reclaim_end"
 atrace_categories: "gfx"
 atrace_categories: "view"
 atrace_apps: "$Package"
} } }
data_sources { config { name: "linux.process_stats" process_stats_config {
 scan_all_processes_on_start: true proc_stats_poll_ms: 1000
} } }
data_sources { config { name: "linux.sys_stats" sys_stats_config {
 stat_period_ms: 1000 stat_counters: STAT_CPU_TIMES
 meminfo_period_ms: 1000 meminfo_counters: MEMINFO_MEM_AVAILABLE
 meminfo_counters: MEMINFO_MEM_FREE meminfo_counters: MEMINFO_SWAP_FREE
 cpufreq_period_ms: 1000
} } }
data_sources { config { name: "android.surfaceflinger.frametimeline" } }
data_sources { config { name: "android.gpu.memory" } }
data_sources { config { name: "android.packages_list" } }
"@
$config | Set-Content "$out/config.pbtxt" -Encoding utf8NoBOM
$remote="/data/local/tmp/redmagic-$id.pbtxt"
$trace="/data/misc/perfetto-traces/redmagic-$id.pftrace"
Adb @('push',"$out/config.pbtxt",$remote) | Out-Null
Adb @('shell',"dumpsys meminfo $Package; dumpsys thermalservice") | Set-Content "$out/before.txt"
# Device-side sampling avoids a separate ADB round trip for each counter.
$sampler=@'
i=0
while [ "$i" -lt SECONDS_PLACEHOLDER ]; do
 echo SAMPLE
 cat /proc/uptime
 head -n 9 /proc/stat
 cat /sys/class/kgsl/kgsl-3d0/gpubusy 2>&1
 cat /sys/class/kgsl/kgsl-3d0/gpuclk 2>&1
 i=$((i+1))
 sleep 1
done
'@
[IO.File]::WriteAllText("$out/sample.sh", $sampler.Replace('SECONDS_PLACEHOLDER',"$Seconds").Replace("`r`n","`n")+"`n", [Text.UTF8Encoding]::new($false))
$rs="/data/local/tmp/redmagic-$id.sh"
Adb @('push',"$out/sample.sh",$rs) | Out-Null
$job=Start-Job -ScriptBlock {param($a,$s,$r) & $a -s $s shell sh $r 2>&1; if($LASTEXITCODE){throw 'Counter sampling failed'}} -ArgumentList $adb,$Serial,$rs
try {
 Write-Host "Recording $Seconds seconds. Play the same scene throughout."
 Adb @('shell',"cat $remote | perfetto --txt -c - -o $trace") | Set-Content "$out/recording.txt"
 Adb @('pull',$trace,"$out/trace.pftrace") | Set-Content "$out/pull.txt"
 if((Get-Item "$out/trace.pftrace").Length -lt 1024){throw 'Trace is unexpectedly small'}
 Wait-Job $job -Timeout ($Seconds+10) | Out-Null
 if($job.State -ne 'Completed'){throw "Sampler state: $($job.State)"}
 Receive-Job $job -ErrorAction Stop | Set-Content "$out/counters.txt"
 Adb @('shell',"dumpsys meminfo $Package; dumpsys thermalservice; ps -A -o USER,PID,PPID,NAME") | Set-Content "$out/after.txt"
 @{package=$Package;serial=$Serial;seconds=$Seconds;traceBytes=(Get-Item "$out/trace.pftrace").Length;status='captured; trace contents require analysis';notes=@('GPU busy is a raw driver counter pair; no unverified utilization conversion.','FrameTimeline is presentation timing, not a guest render or GPU execution breakdown.','FEX/Wine/VKD3D/Turnip attribution requires stack symbols or explicit instrumentation.','No GPU render-stage producer was observed during initial setup.')} | ConvertTo-Json -Depth 5 | Set-Content "$out/summary.json"
} finally {
 Stop-Job $job -ErrorAction SilentlyContinue
 Remove-Job $job -Force -ErrorAction SilentlyContinue
 # Only unique temporary files created by this invocation are removed.
 & $adb -s $Serial shell rm -f $remote $rs $trace | Out-Null
}
Write-Host "Capture saved: $out"


