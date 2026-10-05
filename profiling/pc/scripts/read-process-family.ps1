function ConvertFrom-ProcessFamily {
 param([string[]]$Lines,[string]$GamePid,[hashtable]$Previous=@{},[double]$ElapsedSeconds=0,[double]$TicksPerSecond=100)
 $found=@{};$current=$null
 foreach($line in $Lines){
  if($line -match '^PF (\d+) (\d+) (\d+) (.+)$'){$current=$Matches[1];$found[$current]=@{pid=[int]$current;ppid=[int]$Matches[2];uid=$Matches[3];name=$Matches[4];ticks=$null;start=$null;state='?';rss=$null}}
  elseif($current -and $line -match '^\d+ \(.+\) (\S) (.+)$'){
   $state=$Matches[1];$parts=$Matches[2] -split '\s+'
   if($parts.Count -gt 18){$found[$current].ticks=[double]$parts[10]+[double]$parts[11];$found[$current].start=$parts[18];$found[$current].state=$state}
  }elseif($current -and $line -match '^VmRSS:\s+(\d+)'){$found[$current].rss=[math]::Round([double]$Matches[1]/1024,1)}
 }
 $descendants=@{};if($found.ContainsKey($GamePid)){$descendants[$GamePid]=$true}
 for($pass=0;$pass -lt $found.Count;$pass++){
  $added=$false;foreach($id in $found.Keys){if(-not $descendants.ContainsKey($id) -and $descendants.ContainsKey([string]$found[$id].ppid)){$descendants[$id]=$true;$added=$true}}
  if(-not $added){break}
 }
 $rows=@(foreach($id in $found.Keys){
  $p=$found[$id];$cores=$null
  if($null -ne $p.ticks -and $ElapsedSeconds -gt 0 -and $Previous.ContainsKey($id) -and $Previous[$id].start -eq $p.start -and $null -ne $Previous[$id].ticks){
   $delta=$p.ticks-$Previous[$id].ticks;if($delta -ge 0){$cores=[math]::Round($delta/$TicksPerSecond/$ElapsedSeconds,2)}
  }
  $relation=if($id -eq $GamePid){'Selected game'}elseif($descendants.ContainsKey($id)){'Game descendant'}else{'Same app account; relationship unconfirmed'}
  [pscustomobject]@{pid=$p.pid;ppid=$p.ppid;name=$p.name;state=$p.state;rss_mb=$p.rss;cpu_cores=$cores;relation=$relation}
 })
 [pscustomobject]@{rows=@($rows | Sort-Object @{Expression={if($_.relation -eq 'Selected game'){0}else{1}}},@{Expression={$_.cpu_cores};Descending=$true});previous=$found}
}
