$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../scripts/read-storage.ps1')
function Sample($total,$wait,$major,$pageIn,$start=99,$state='S',$direct=$false){
 $fields=@('0')*49;$fields[8]="$major";$fields[18]="$start"
 $lines=@('CPU',"cpu $total 0 0 0 $wait 0 0 0",'SWAPIO',"pgpgin $pageIn",'pgpgout 0','GAME',('7 (game (test).exe) S '+($fields -join ' ')),'THREADS',"7 (main) $state 0",'STORAGE')
 if($direct){$lines+=@("GAMEIO read_bytes: $($pageIn*1024)",'GAMEIO write_bytes: 0',"PSI some avg10=0.00 avg60=0.00 avg300=0.00 total=$($wait*10000)")}
 $lines
}
function Check($ok,$why){if(-not $ok){throw $why}}
$a=ConvertFrom-StorageSample -Lines (Sample 1000 10 5 1024) -DeviceSeconds 100
Check ($null -eq $a.data.io_wait_percent -and $null -eq $a.data.game_major_faults_s) 'First sample fabricated rates'
Check ($a.data.throughput_status -like 'Unavailable*') 'Denied I/O fabricated throughput'
$b=ConvertFrom-StorageSample -Lines (Sample 1600 10 5 1024) -Previous $a.previous -DeviceSeconds 103
Check ($b.data.io_wait_percent -eq 0 -and $b.data.game_major_faults_s -eq 0) 'Real zero lost'
Check ($b.data.status -eq 'No strong storage-stall evidence') 'Idle flagged as bottleneck'
$c=ConvertFrom-StorageSample -Lines (Sample 2180 30 35 4096 99 'D') -Previous $b.previous -DeviceSeconds 106 -FrameP95 60
Check ([math]::Abs($c.data.io_wait_percent-100*20/600) -lt 0.001) 'I/O wait denominator incorrect'
Check ($c.data.game_major_faults_s -eq 10 -and $c.data.phone_page_in_mib_s -eq 1) 'Fault/page-in units incorrect'
Check ($c.data.game_blocked_threads -eq 1 -and $c.data.status -eq 'Possible storage stalls with slow frames') 'Combined pressure missed'
$d=ConvertFrom-StorageSample -Lines (Sample 2780 30 65 7168) -Previous $c.previous -DeviceSeconds 109 -FrameP95 60
Check ($d.data.status -eq 'Game read / paging activity') 'Paging alone blamed for slow frames'
$e=ConvertFrom-StorageSample -Lines (Sample 3380 30 999 7168 101) -Previous $d.previous -DeviceSeconds 112
Check ($null -eq $e.data.game_major_faults_s) 'PID reuse gave stale game rate'
$reset=ConvertFrom-StorageSample -Lines (Sample 10 1 1 1) -Previous $d.previous -DeviceSeconds 2
Check ($null -eq $reset.data.io_wait_percent -and $null -eq $reset.data.game_major_faults_s) 'Reboot fabricated rates'
$counterReset=ConvertFrom-StorageSample -Lines (Sample 10 1 1 1) -Previous $d.previous -DeviceSeconds 112
Check ($null -eq $counterReset.data.io_wait_percent -and $null -eq $counterReset.data.game_major_faults_s -and $null -eq $counterReset.data.phone_page_in_mib_s) 'Counter regression fabricated rates'
$gap=ConvertFrom-StorageSample -Lines (Sample 4000 30 65 7168) -Previous $d.previous -DeviceSeconds 150
Check ($null -eq $gap.data.io_wait_percent) 'Long pause included in rate window'
$missing=ConvertFrom-StorageSample -Lines @('CPU','GAME','THREADS','STORAGE') -Previous $d.previous -DeviceSeconds 112
Check ($null -eq $missing.data.game_blocked_threads -and $null -eq $missing.data.io_wait_percent) 'Missing source turned into zero'
$io1=ConvertFrom-StorageSample -Lines (Sample 1000 10 5 1024 99 'S' $true) -DeviceSeconds 100
$io2=ConvertFrom-StorageSample -Lines (Sample 1580 30 5 4096 99 'S' $true) -Previous $io1.previous -DeviceSeconds 103
Check ($io2.data.game_read_mib_s -eq 1 -and $io2.data.psi_some_percent -gt 6) 'Optional readable I/O/PSI not handled'
Check ($io2.data.throughput_status -like 'Game process actual*') 'Measured I/O source mislabeled'
'PASS: storage warm-up, deltas, units, heuristic, permission gaps, PID reuse, reboot and pause reset'
