function ConvertFrom-StorageSample {
 param([string[]]$Lines,[hashtable]$Previous=@{},[double]$DeviceSeconds=0,[datetime]$At=(Get-Date),[double]$FrameP95=0,[double]$FrameBudget=16.67)
 $current=@{at=$DeviceSeconds};$section='';$blocked=$null
 foreach($item in $Lines){
  $line=$item.Trim()
  if($line -in @('CPU','FREQ','LIMIT','GPU','MEM','SWAPIO','THERMAL','GAME','FAMILY','BACKEND','THREADS','STORAGE','BACKGROUND','FEXJIT','APPPROFILE','UPTIME')){$section=$line;continue}
  if($section -eq 'CPU' -and $line -match '^cpu\s+(.+)$'){
   $v=@($Matches[1] -split '\s+' | ForEach-Object {[double]$_})
   if($v.Count -ge 8){$current.total=($v[0..7] | Measure-Object -Sum).Sum;$current.wait=$v[4]}
  }
  if($section -eq 'SWAPIO' -and $line -match '^(pgpgin|pgpgout) (\d+)$'){$current[$Matches[1]]=[double]$Matches[2]}
  if($section -eq 'GAME' -and $line -match '^(\d+) \(.+\) \S (.+)$'){
   $processId=$Matches[1];$v=$Matches[2] -split '\s+'
   if($v.Count -ge 19){$current.identity=$processId+':'+$v[18];$current.major=[double]$v[8]}
  }
  if($section -eq 'THREADS' -and $line -match '^\d+ \(.+\) (\S) '){if($null -eq $blocked){$blocked=0};if($Matches[1] -eq 'D'){$blocked++}}
  if($section -eq 'STORAGE'){
   if($line -match '^GAMEIO (read_bytes|write_bytes):\s*(\d+)$'){$current[$Matches[1]]=[double]$Matches[2]}
   if($line -match '^PSI (some|full) .*total=(\d+)$'){$current['psi_'+$Matches[1]]=[double]$Matches[2]}
  }
 }
 $result=[ordered]@{sampled_at=$At.ToString('o');window_seconds=$null;status='Warming up: needs two storage samples';evidence='Sampled signals; disk saturation is not measured';io_wait_percent=$null;phone_page_in_mib_s=$null;phone_page_out_mib_s=$null;game_major_faults_s=$null;game_read_mib_s=$null;game_write_mib_s=$null;game_blocked_threads=$blocked;psi_some_percent=$null;psi_full_percent=$null;throughput_status='Unavailable: game I/O counters restricted or missing';psi_status='Unavailable: I/O pressure counters restricted or missing';frame_p95_ms=$(if($FrameP95 -gt 0){$FrameP95}else{$null})}
 $elapsed=$DeviceSeconds-$Previous.at
 if($Previous.Count -and $elapsed -gt 0 -and $elapsed -le 30){
  $result.window_seconds=$elapsed
  $sameGame=$current.identity -and $current.identity -eq $Previous.identity
  foreach($pair in @(@('pgpgin','phone_page_in_mib_s'),@('pgpgout','phone_page_out_mib_s'),@('major','game_major_faults_s'),@('read_bytes','game_read_mib_s'),@('write_bytes','game_write_mib_s'),@('psi_some','psi_some_percent'),@('psi_full','psi_full_percent'))){
   $key=$pair[0]
   if($key -in @('major','read_bytes','write_bytes') -and -not $sameGame){continue}
   if($current.ContainsKey($key) -and $Previous.ContainsKey($key)){
    $delta=$current[$key]-$Previous[$key]
    if($delta -ge 0){
     $scale=if($key -like 'pgpg*'){1024.0}elseif($key -like '*_bytes'){1048576.0}elseif($key -like 'psi_*'){10000.0}else{1.0}
     $value=$delta/$elapsed/$scale
     if($key -like 'psi_*' -and $value -gt 100){continue}
     $result[$pair[1]]=$value
    }
   }
  }
  if($current.ContainsKey('total') -and $Previous.ContainsKey('total') -and $current.total -gt $Previous.total){
   $delta=$current.wait-$Previous.wait;$total=$current.total-$Previous.total
   if($delta -ge 0 -and $delta -le $total){$result.io_wait_percent=100*$delta/$total}
  }
  $gameActivity=($result.game_major_faults_s -gt 0 -or $result.game_read_mib_s -gt 0)
  $pressure=($result.psi_some_percent -ge 5 -or $result.io_wait_percent -ge 2)
  $linked=($gameActivity -and ($pressure -or $blocked -gt 0)) -or ($blocked -gt 0 -and $pressure)
  $result.status=if($linked -and $FrameP95 -gt 1.5*$FrameBudget){'Possible storage stalls with slow frames'}elseif($linked){'Possible storage stalls'}elseif($pressure){'Phone I/O pressure; game link uncertain'}elseif($gameActivity){'Game read / paging activity'}elseif($null -ne $result.io_wait_percent -or $null -ne $result.game_major_faults_s){'No strong storage-stall evidence'}else{'Unavailable: storage signals missing or counters reset'}
  $result.evidence='Heuristic: game reads/page faults or blocked threads + I/O pressure. D-state can include other kernel waits; paging can include swap. Slow frames are coincident, not proven caused by storage.'
 }
 if(-not $current.identity){$result.status='Waiting for a readable game process'}
 if($current.ContainsKey('read_bytes')){$result.throughput_status=if($null -ne $result.game_read_mib_s){'Game process actual I/O bytes; excludes cached reads and helpers'}else{'Warming up: game I/O needs two samples'}}
 if($current.ContainsKey('psi_some')){$result.psi_status=if($null -ne $result.psi_some_percent){'Phone-wide time stalled on I/O'}else{'Warming up: I/O pressure needs two samples'}}
 [pscustomobject]@{data=[pscustomobject]$result;previous=$current}
}
