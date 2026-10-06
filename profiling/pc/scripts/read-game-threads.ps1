function Format-CpuWork {
 param($MsPerSecond,[string]$Status='Warming up: needs two live samples')
 if($null -eq $MsPerSecond){return $Status}
 return ('{0:N2} busy cores · {1:N0} CPU ms/s' -f ($MsPerSecond/1000),$MsPerSecond)
}
function ConvertFrom-GameThreads {
 param([string[]]$Lines,[hashtable]$Previous=@{},[double]$ElapsedSeconds=0)
 $current=@{};$schedulers=@{}
 foreach($line in $Lines){
  if($line -match '^SCHED /proc/\d+/task/(\d+)/schedstat (\d+) (\d+) (\d+)$'){
   $schedulers[$Matches[1]]=@{run=[double]$Matches[2];wait=[double]$Matches[3];slices=[double]$Matches[4]}
  }
 }
 $rows=@(foreach($line in $Lines){
  if($line -notmatch '^(\d+) \((.+)\) (\S) (.+)$'){continue}
  $id=$Matches[1];$name=$Matches[2];$state=$Matches[3];$fields=$Matches[4] -split '\s+'
  if($fields.Count -lt 36){continue}
  $ticks=[double]$fields[10]+[double]$fields[11];$start=$fields[18];$lastCore=[int]$fields[35]
  $type=if($name -like 'dxvk-shader-*'){'shader'}elseif($name -in @('dxvk-submit','dxvk-queue')){'submit'}elseif($name -like 'dxvk-*'){'dxvkOther'}elseif($name -match '^(vkd3d|d3dvk)'){'vkd3d'}elseif($name -like 'd8vk*'){'d8vk'}elseif($name -like 'wine_*'){'wineInGame'}else{'other'}
  $role=if($type -eq 'shader'){'DXVK shader worker'}elseif($type -eq 'submit'){'DXVK submission worker'}elseif($type -eq 'dxvkOther'){'Other DXVK worker'}elseif($type -eq 'vkd3d'){'VKD3D / D3DVK worker'}elseif($type -eq 'd8vk'){'D8VK worker'}elseif($type -eq 'wineInGame'){'Wine worker'}elseif($name -match '(?i)audio|AK::|FAudio'){'Audio'}elseif($name -match '(?i)load|file|disk'){'Loading / file work'}elseif($name -match '(?i)EngineWindow'){'Engine / window worker'}elseif($name -match '(?i)TaskThread'){'Game task worker'}else{'Unknown'}
  $rate=$null;$status='Warming up: new thread or first sample'
  if($ElapsedSeconds -gt 0 -and $Previous.ContainsKey($id) -and $Previous[$id].start -eq $start){
   $delta=$ticks-$Previous[$id].ticks
   if($delta -ge 0){$rate=10*$delta/$ElapsedSeconds;$status='Measured between live samples'}else{$status='Unavailable: CPU counter reset'}
  }
  $queue=$null;$scheduled=$null;$queueStatus='Unavailable: scheduler counters not readable'
  $sched=$schedulers[$id]
  if($sched){
   $queueStatus='Warming up: needs two scheduler samples'
   if($ElapsedSeconds -gt 0 -and $Previous.ContainsKey($id) -and $Previous[$id].start -eq $start -and $Previous[$id].scheduler){
    $old=$Previous[$id].scheduler;$runDelta=$sched.run-$old.run;$waitDelta=$sched.wait-$old.wait
    if($runDelta -lt 0 -or $waitDelta -lt 0 -or $sched.slices -lt $old.slices){$queueStatus='Unavailable: scheduler counter reset'}
    elseif($sched.run -eq 0 -and $sched.wait -eq 0 -and $sched.slices -eq 0){$queueStatus='Unavailable: scheduler counters inactive'}
    else{$queue=$waitDelta/1000000/$ElapsedSeconds;$scheduled=$runDelta/1000000/$ElapsedSeconds;$queueStatus='Measured runnable wait; excludes sleeping and blocked waits'}
   }
  }
  $current[$id]=@{ticks=$ticks;start=$start;type=$type;scheduler=$sched}
  [pscustomobject]@{tid=[int]$id;name=$name;state=$state;last_core=$lastCore;role=$role;type=$type;cpu_ms_per_s=$rate;cpu_cores=$(if($null -ne $rate){$rate/1000}else{$null});cpu_percent=$(if($null -ne $rate){$rate/10}else{$null});status=$status;cpu_queue_ms_per_s=$queue;scheduled_ms_per_s=$scheduled;queue_status=$queueStatus}
 })
 $groups=@{}
 foreach($type in @('shader','submit','dxvkOther','vkd3d','d8vk','wineInGame')){
  $all=@($rows | Where-Object type -eq $type);$measured=@($all | Where-Object {$null -ne $_.cpu_ms_per_s})
  $rate=if($measured.Count){($measured | Measure-Object cpu_ms_per_s -Sum).Sum}else{$null}
  $status=if(-not $all.Count){'No named worker seen'}elseif(-not $measured.Count){'Warming up: needs two samples from the same threads'}else{"$($measured.Count)/$($all.Count) named threads measured"}
  $groups[$type]=[pscustomobject]@{cpu_ms_per_s=$rate;cpu_cores=$(if($null -ne $rate){$rate/1000}else{$null});status=$status;count=$all.Count;measured=$measured.Count}
 }
 [pscustomobject]@{rows=@($rows | Sort-Object @{Expression={if($null -eq $_.cpu_ms_per_s){-1}else{$_.cpu_ms_per_s}};Descending=$true});previous=$current;groups=$groups}
}
