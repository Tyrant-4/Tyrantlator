. "$PSScriptRoot/../scripts/read-game-threads.ps1"
function ThreadLine($tid,$name,$ticks,$start=100,$core=6){
 $parts=@(1)+@(0)*9+@($ticks,0)+@(0)*6+@($start)+@(0)*16+@($core)
 "$tid ($name) S $($parts -join ' ')"
}
$a=ConvertFrom-GameThreads -Lines @((ThreadLine 10 'dxvk-submit' 100),(ThreadLine 11 'dxvk-shader-0' 20),(ThreadLine 12 'TaskThread 0' 200))
if($null -ne $a.rows[0].cpu_ms_per_s -or $a.groups.submit.cpu_ms_per_s -ne $null){throw 'First sample fabricated zero'}
$b=ConvertFrom-GameThreads -Lines @((ThreadLine 10 'dxvk-submit' 200),(ThreadLine 11 'dxvk-shader-0' 20),(ThreadLine 12 'TaskThread 0' 220)) -Previous $a.previous -ElapsedSeconds 2
if($b.groups.submit.cpu_ms_per_s -ne 500 -or $b.groups.submit.cpu_cores -ne .5){throw 'Rate not normalized by elapsed seconds'}
if($b.groups.shader.cpu_ms_per_s -ne 0){throw 'Measured idle worker lost'}
if($b.rows[0].tid -ne 10 -or $b.rows[0].cpu_percent -ne 50 -or $b.rows[0].last_core -ne 6){throw 'Thread sort, percent or CPU field incorrect'}
$c=ConvertFrom-GameThreads -Lines @((ThreadLine 10 'dxvk-submit' 400 999)) -Previous $a.previous -ElapsedSeconds 2
if($null -ne $c.rows[0].cpu_ms_per_s){throw 'Reused TID inherited previous ticks'}
$partial=ConvertFrom-GameThreads -Lines @((ThreadLine 10 'dxvk-submit' 200),(ThreadLine 13 'dxvk-queue' 500 300)) -Previous $a.previous -ElapsedSeconds 2
if($partial.groups.submit.measured -ne 1 -or $partial.groups.submit.count -ne 2){throw 'Partial coverage hidden'}
$missing=ConvertFrom-GameThreads -Lines @('broken')
if($missing.rows.Count -ne 0 -or $missing.groups.submit.status -ne 'No named worker seen'){throw 'Missing worker fabricated'}
if((Format-CpuWork -MsPerSecond 500) -notmatch '0.50 busy cores'){throw 'CPU display units incorrect'}
'PASS: normalized rates, idle vs warmup, last core, TID reuse, grouping and partial coverage'
function SchedLine($tid,$run,$wait,$slices=10){"SCHED /proc/500/task/$tid/schedstat $run $wait $slices"}
$q1=ConvertFrom-GameThreads -Lines @((ThreadLine 10 'EngineWindowThr' 100),(SchedLine 10 1000000000 200000000))
$q2=ConvertFrom-GameThreads -Lines @((ThreadLine 10 'EngineWindowThr' 200),(SchedLine 10 2000000000 600000000 20)) -Previous $q1.previous -ElapsedSeconds 2
if($q2.rows[0].cpu_queue_ms_per_s -ne 200 -or $q2.rows[0].scheduled_ms_per_s -ne 500){throw 'Scheduler rates not normalized'}
$qr=ConvertFrom-GameThreads -Lines @((ThreadLine 10 'EngineWindowThr' 300 999),(SchedLine 10 3000000000 900000000 30)) -Previous $q1.previous -ElapsedSeconds 2
if($null -ne $qr.rows[0].cpu_queue_ms_per_s){throw 'Reused thread inherited queue wait'}
$zero1=ConvertFrom-GameThreads -Lines @((ThreadLine 10 'worker' 100),(SchedLine 10 0 0 0))
$zero2=ConvertFrom-GameThreads -Lines @((ThreadLine 10 'worker' 200),(SchedLine 10 0 0 0)) -Previous $zero1.previous -ElapsedSeconds 2
if($null -ne $zero2.rows[0].cpu_queue_ms_per_s -or $zero2.rows[0].queue_status -notmatch 'inactive'){throw 'Disabled counters presented as no wait'}
$reset=ConvertFrom-GameThreads -Lines @((ThreadLine 10 'worker' 200),(SchedLine 10 900000000 100000000)) -Previous $q1.previous -ElapsedSeconds 2
if($null -ne $reset.rows[0].cpu_queue_ms_per_s -or $reset.rows[0].queue_status -notmatch 'reset'){throw 'Counter reset fabricated queue rate'}
$missingSched=ConvertFrom-GameThreads -Lines @((ThreadLine 10 'worker' 200)) -Previous $q1.previous -ElapsedSeconds 2
if($null -ne $missingSched.rows[0].cpu_queue_ms_per_s -or $missingSched.rows[0].queue_status -notmatch 'not readable'){throw 'Missing scheduler source fabricated queue rate'}
'PASS: scheduler queue units, TID reuse, inactive counters, resets and missing-source handling'
$g1=ConvertFrom-GameThreads -Lines @((ThreadLine 20 'dxvk-cs' 100),(ThreadLine 21 'dxvk-shader-0' 100),(ThreadLine 22 'dxvk-shader-1' 100),(SchedLine 20 1000000000 100000000),(SchedLine 21 1000000000 100000000))
$g2=ConvertFrom-GameThreads -Lines @((ThreadLine 20 'dxvk-cs' 200),(ThreadLine 21 'dxvk-shader-0' 150),(ThreadLine 22 'dxvk-shader-1' 100),(SchedLine 20 2000000000 500000000 20),(SchedLine 21 1500000000 300000000 20)) -Previous $g1.previous -ElapsedSeconds 2
if($g2.groups.command.cpu_ms_per_s -ne 500 -or $g2.groups.command.cpu_queue_ms_per_s -ne 200 -or $g2.groups.dxvkOther.count -ne 0){throw 'Command stream grouping or queue aggregation incorrect'}
if($g2.groups.shader.active -ne 1 -or $g2.groups.shader.count -ne 2 -or $g2.groups.shader.queue_measured -ne 1 -or $g2.groups.shader.cpu_queue_ms_per_s -ne 100){throw 'Shader activity/partial queue coverage incorrect'}
if($null -ne $g1.groups.shader.active){throw 'Unmeasured shader workers labeled idle'}
'PASS: graphics command grouping, active vs idle workers and partial queue coverage'
