function ConvertFrom-BackgroundCpu {
 param([string[]]$Lines,[string]$GamePid,[string]$Package='',[object[]]$Family=@(),[hashtable]$Previous=@{},[datetime]$At=(Get-Date))
 $known=@{};foreach($p in $Family){$known[[string]$p.pid]=$p}
 $tracker=@{};$alerts=New-Object 'System.Collections.Generic.List[object]'
 $rows=@(foreach($line in $Lines){
  if($line -notmatch '^\s*(\d+)\s+(\d+)\s+(\d+)\s+(\S)\s+(\d+(?:\.\d+)?)\s+(.+)$'){continue}
  $id=$Matches[1];$parent=[int]$Matches[2];$uid=[int]$Matches[3];$state=$Matches[4];$percent=[double]::Parse($Matches[5],[cultureinfo]::InvariantCulture);$name=$Matches[6]
  $relation='Other process; relationship unconfirmed';$protected=$false
  if($id -eq $GamePid){$relation='Selected game';$protected=$true}
  elseif($known.ContainsKey($id) -and $known[$id].relation -eq 'Game descendant'){$relation='Game descendant';$protected=$true}
  elseif($Package -and ($name -eq $Package -or $name.StartsWith($Package+':'))){$relation='Emulator host app';$protected=$true}
  elseif($name -match '^(top|adbd|sh)$'){$relation='Profiler / command transport';$protected=$true}
  elseif($name -match 'surfaceflinger|display\.composer'){$relation='Android display service';$protected=$true}
  elseif($name -eq 'system_server' -or $name.StartsWith('[')){$relation='Android system / kernel';$protected=$true}
  elseif($known.ContainsKey($id)){$relation='Same app account; relationship unconfirmed'}
  $key="$id|$uid|$name";$since=$At
  if($percent -ge 50 -and -not $protected -and $GamePid -ne 'Unavailable'){
   if($Previous.ContainsKey($key) -and ($At-$Previous[$key].last).TotalSeconds -le 10){$since=$Previous[$key].since}
   $tracker[$key]=@{since=$since;last=$At}
   if(($At-$since).TotalSeconds -ge 5){
    $title=if($state -eq 'Z'){'Exited main thread with active CPU'}else{'Sustained CPU outside confirmed game processes'}
    [void]$alerts.Add([pscustomobject]@{pid=[int]$id;name=$name;title=$title;seconds=[math]::Round(($At-$since).TotalSeconds);cpu_cores=[math]::Round($percent/100,2);detail='Check its purpose before stopping it. This is a candidate, not proof it is unnecessary or causing slow frames.'})
   }
  }
  [pscustomobject]@{pid=[int]$id;ppid=$parent;uid=$uid;name=$name;state=$state;cpu_cores=[math]::Round($percent/100,2);relation=$relation}
 })
 [pscustomobject]@{status=$(if($rows.Count){'Live top 15 processes by CPU; independent short phone-side process sample'}else{'Unavailable: phone process sample missing'});processes=$rows;alerts=@($alerts.ToArray());previous=$tracker}
}
