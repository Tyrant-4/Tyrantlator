. "$PSScriptRoot/../scripts/read-background-cpu.ps1"
$at=[datetime]'2026-10-05T12:00:00'
$lines=@('PID PPID UID S %CPU NAME','30203 1 10536 S 400 ACOrigins.exe','99 1 10536 Z 200 CrBrowserMain','1827 1 1000 S 80 surfaceflinger','55 1 2000 R 60 top','70 1 10600 S 80 music.player')
$a=ConvertFrom-BackgroundCpu -Lines $lines -GamePid 30203 -At $at
if($a.processes.Count -ne 5 -or $a.alerts.Count -ne 0){throw 'Bad initial parsing or premature alert'}
$b=ConvertFrom-BackgroundCpu -Lines $lines -GamePid 30203 -At $at.AddSeconds(6) -Previous $a.previous
if($b.alerts.Count -ne 2){throw 'Did not distinguish competing activity from game/display/profiler'}
if(($b.processes | Where-Object pid -eq 99).cpu_cores -ne 2){throw 'Exited leader CPU was lost'}
if(($b.alerts | Where-Object pid -eq 99).title -notmatch 'Exited'){throw 'Missing remaining-thread indication'}
$c=ConvertFrom-BackgroundCpu -Lines $lines -GamePid 30203 -At $at.AddSeconds(20) -Previous $a.previous
if($c.alerts.Count -ne 0){throw 'Gap falsely counted as continuous activity'}
$d=ConvertFrom-BackgroundCpu -Lines $lines -GamePid Unavailable -At $at.AddSeconds(6) -Previous $a.previous
if($d.alerts.Count -ne 0){throw 'Alerts attributed to absent game'}
$e=ConvertFrom-BackgroundCpu -Lines @() -GamePid 30203
if($e.status -notmatch 'Unavailable'){throw 'Missing source hidden'}
$f=ConvertFrom-BackgroundCpu -Lines @('70 1 10600 S 80 gameChild.exe') -GamePid 30203 -At $at.AddSeconds(6) -Previous $a.previous -Family @([pscustomobject]@{pid=70;relation='Game descendant'})
if($f.alerts.Count -ne 0 -or $f.processes[0].relation -ne 'Game descendant'){throw 'Confirmed descendant wrongly warned'}
'PASS: parsing, CPU units, sustained alerts, protected services, exited leader, sampling gaps, absent game and descendants'
$hostCheck=ConvertFrom-BackgroundCpu -Lines @('99 1 10536 S 90 com.tencent.ig') -GamePid 30203 -Package com.tencent.ig -At $at
if($hostCheck.processes[0].relation -ne 'Emulator host app' -or $hostCheck.previous.Count -ne 0){throw 'Host app wrongly classified as unrelated'}
'PASS: emulator host recognized'
