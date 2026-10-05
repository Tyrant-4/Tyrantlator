. "$PSScriptRoot/../scripts/read-process-family.ps1"
function Stat($id,$parent,$ticks,$start,$state='S'){
 $fields=@($parent)+@(0)*9+@($ticks,0)+@(0)*6+@($start)
 "$id (name with spaces) $state $($fields -join ' ')"
}
$lines=@('PF 10 1 10001 ACOrigins.exe',(Stat 10 1 100 200),'VmRSS: 2048 kB','PF 11 10 10001 child.exe',(Stat 11 10 30 201),'PF 12 1 10001 upc.exe',(Stat 12 1 50 202),'PF 13 1 10001 CrBrowserMain',(Stat 13 1 500 203 Z))
$a=ConvertFrom-ProcessFamily -Lines $lines -GamePid 10
$b=ConvertFrom-ProcessFamily -Lines ($lines -replace ' 100 0 ',' 200 0 ') -GamePid 10 -Previous $a.previous -ElapsedSeconds 2
if(($b.rows | Where-Object pid -eq 10).cpu_cores -ne .5){throw 'CPU delta incorrect'}
if(($b.rows | Where-Object pid -eq 11).relation -ne 'Game descendant'){throw 'Descendant relation incorrect'}
if(($b.rows | Where-Object pid -eq 12).relation -notmatch 'unconfirmed'){throw 'Shared UID wrongly treated as game family'}
if($null -ne ($b.rows | Where-Object pid -eq 13).cpu_cores){throw 'Zombie counted as active CPU'}
$c=ConvertFrom-ProcessFamily -Lines @('PF 10 1 10001 ACOrigins.exe',(Stat 10 1 900 999)) -GamePid 10 -Previous $a.previous -ElapsedSeconds 2
if($null -ne $c.rows[0].cpu_cores){throw 'Reused PID inherited old CPU ticks'}
$e=ConvertFrom-ProcessFamily -Lines @() -GamePid Unavailable
if($e.rows.Count -ne 0){throw 'Missing game should have no family'}
'PASS: process ancestry, CPU deltas, PID reuse, zombies and missing process'
