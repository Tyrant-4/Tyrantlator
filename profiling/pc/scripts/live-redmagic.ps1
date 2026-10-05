param(
 [ValidateRange(1,21600)][int]$Seconds=3600,
 [ValidatePattern('^[A-Za-z0-9_.]+$')][string]$Package='auto',
 [ValidatePattern('^[A-Za-z0-9_.-]+$')][string]$GameProcess='auto',
 [ValidatePattern('^[A-Za-z0-9]+$')][string]$Serial='9126023101C5',
 [string]$ProjectRoot=(Split-Path $PSScriptRoot -Parent),
 [ValidateRange(15,240)][int]$TargetFps=60,
 [string]$LogDirectory='',
 [string]$DashboardDataPath=''
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'read-app-profile.ps1')
. (Join-Path $PSScriptRoot 'read-process-family.ps1')
. (Join-Path $PSScriptRoot 'read-background-cpu.ps1')
$previousBackground=@{}
$previousFamily=@{};$previousFamilyAt=$null
$targetMs=1000.0/$TargetFps
$adb=Join-Path $ProjectRoot 'platform-tools-latest-windows/platform-tools/adb.exe'
# ADB writes its normal server-start notice to stderr. Windows PowerShell 5
# treats that notice as a terminating error when ErrorActionPreference is Stop.
$adbCheck=[System.Diagnostics.ProcessStartInfo]::new()
$adbCheck.FileName=$adb
$adbCheck.Arguments="-s $Serial get-state"
$adbCheck.UseShellExecute=$false
$adbCheck.RedirectStandardOutput=$true
$adbCheck.RedirectStandardError=$true
$adbProcess=[System.Diagnostics.Process]::Start($adbCheck)
$state=$adbProcess.StandardOutput.ReadToEnd().Trim()
$adbError=$adbProcess.StandardError.ReadToEnd().Trim()
$adbProcess.WaitForExit()
if($adbProcess.ExitCode -ne 0 -or $state -ne 'device'){
 throw "Phone is not connected or authorized: $state $adbError"
}
$previousCpu=@{}; $previousGame=$null
$previousWine=@{}
$previousThreads=@{}
$previousJit=@{}
$previousSwap=$null
$gpuRecent=New-Object 'System.Collections.Generic.List[double]'
$dashboardHistory=New-Object 'System.Collections.Generic.List[object]'
$dashboardEvents=New-Object 'System.Collections.Generic.List[object]'
$lastEvent=@{}
$trackedGamePid=$null
$allowedBaseline=@{}
$surfaceLayer=$null; $activePackage=$Package; $lastFrameReady=[long]0
$staleSurfaceSamples=0
$timingHistory=New-Object 'System.Collections.Generic.List[double]'
if(-not $LogDirectory){$LogDirectory=Join-Path $ProjectRoot 'work\live-sessions'}
New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null
$sessionId=Get-Date -Format 'yyyyMMdd-HHmmss'
$logPath=Join-Path $LogDirectory ('redmagic-'+$sessionId+'.csv')
if(-not $DashboardDataPath){$DashboardDataPath=Join-Path $ProjectRoot 'work\live-sessions\live-data.js'}
New-Item -ItemType Directory -Path (Split-Path -Parent $DashboardDataPath) -Force | Out-Null
function Add-ProfileEvent {
 param([string]$Kind,[string]$Title,[string]$Detail,[datetime]$At,[int]$CooldownSeconds=12)
 if($lastEvent.ContainsKey($Kind) -and ($At-$lastEvent[$Kind]).TotalSeconds -lt $CooldownSeconds){return}
 $lastEvent[$Kind]=$At
 [void]$dashboardEvents.Add([pscustomobject]@{time=$At.ToString('HH:mm:ss');kind=$Kind;title=$Title;detail=$Detail})
 if($dashboardEvents.Count -gt 40){$dashboardEvents.RemoveAt(0)}
}
function Show-TimingGraph {
 Write-Host 'SURFACE TIMING GRAPH - last 60 updates, newest at right' -ForegroundColor Cyan
 if($timingHistory.Count -eq 0){Write-Host 'Waiting for surface timing samples';return}
 $levels=@(50.0,40.0,30.0,20.0,$targetMs,10.0,5.0) | Sort-Object -Descending -Unique
 foreach($level in $levels){
  $bar=New-Object System.Text.StringBuilder
  foreach($value in $timingHistory){
   $mark=if($value -ge $level){if($level -eq 50.0 -and $value -gt 50.0){'^'}else{'#'}}elseif($level -eq $targetMs){'-'}else{' '}
   [void]$bar.Append($mark)
  }
  $label=if($level -eq $targetMs){'{0:N1}' -f $level}else{('{0:N0}' -f $level)}
  $color=if($level -eq $targetMs){'Yellow'}elseif($level -ge 30){'Magenta'}else{'Gray'}
  Write-Host ('{0,4} |{1}' -f $label,$bar.ToString()) -ForegroundColor $color
 }
 Write-Host ('      # = interval reached level; ^ = over 50 ms; dashed = {0} FPS target' -f $TargetFps) -ForegroundColor DarkGray
}
function Get-ActiveGameSurface {
 $list=& $adb -s $Serial shell 'dumpsys SurfaceFlinger --list' 2>$null
 $candidates=@($list | ForEach-Object {
  if($_ -match '([a-f0-9]+ SurfaceView\[[^\]]+\]\(BLAST\)#\d+)'){
   $candidate=$Matches[1]
   if($candidate -match 'XServer' -or ($Package -ne 'auto' -and $candidate -match ('\['+[regex]::Escape($Package)+'/'))){$candidate}
  }
 })
 $best=[long]0;$selected=$null
 foreach($candidate in $candidates){
  $rows=& $adb -s $Serial shell "dumpsys SurfaceFlinger --latency '$candidate'" 2>$null
  foreach($row in $rows){
   if($row -match '^\d+\s+\d+\s+([1-9]\d+)$'){
    $stamp=[long]$Matches[1]
    if($stamp -gt $best){$best=$stamp;$selected=$candidate}
   }
  }
 }
 return $selected
}
$until=(Get-Date).AddSeconds($Seconds)
$shell=@'
echo CPU
head -n 9 /proc/stat
echo FREQ
for c in 0 1 2 3 4 5 6 7; do cat /sys/devices/system/cpu/cpu$c/cpufreq/scaling_cur_freq 2>/dev/null || echo 0; done
echo LIMIT
for c in 0 1 2 3 4 5 6 7; do
 read allowed < /sys/devices/system/cpu/cpu$c/cpufreq/scaling_max_freq 2>/dev/null || allowed=0
 read hardware < /sys/devices/system/cpu/cpu$c/cpufreq/cpuinfo_max_freq 2>/dev/null || hardware=0
 echo "$allowed $hardware"
done
echo GPU
cat /sys/class/kgsl/kgsl-3d0/gpubusy 2>/dev/null || echo unavailable
echo MEM
grep -E 'MemTotal:|MemAvailable:|SwapTotal:|SwapFree:' /proc/meminfo
echo SWAPIO
grep -E '^pswp(in|out) ' /proc/vmstat
echo THERMAL
for zone in /sys/class/thermal/thermal_zone*; do
 read sensor < "$zone/type" 2>/dev/null || continue
 case "$sensor" in
  cpu-0-*|cpu-1-*|gpuss-*|skin-msm-therm|battery)
   read temperature < "$zone/temp" 2>/dev/null || continue
   echo "$sensor $temperature"
   ;;
 esac
done
echo WINE
ps -A -o PID,NAME | grep -Ei 'wineserver$|winedevice\.exe$' | while read winePid wineName; do
 echo "PID $winePid $wineName"
 cat /proc/$winePid/stat 2>/dev/null
done
echo GAME
gamePid=''
gameName=''
if [ 'GAME_PLACEHOLDER' = auto ]; then
 bestRss=0
 for candidatePid in $(ps -A -o PID,NAME | awk 'tolower($0) ~ /\.exe$/ && $1 ~ /^[0-9]+$/ { print $1 }'); do
  read candidateName < "/proc/$candidatePid/comm" 2>/dev/null || continue
  case "$candidateName" in
   wineserver|winedevice.exe|services.exe|explorer.exe|plugplay.exe|rpcss.exe|conhost.exe|start.exe|svchost.exe|rundll32.exe|msiexec.exe|cmd.exe|taskmgr.exe|winecfg.exe|steam.exe|xalia.exe|tabtip.exe|upc.exe|CrGpuMain|CrRendererMain|UbisoftGameLaun) continue ;;
  esac
  candidateRss=$(awk '/^VmRSS:/ { print $2; exit }' "/proc/$candidatePid/status" 2>/dev/null)
  case "$candidateRss" in ''|*[!0-9]*) continue ;; esac
  if [ "$candidateRss" -gt "$bestRss" ]; then
   bestRss=$candidateRss; gamePid=$candidatePid; gameName=$candidateName
  fi
 done
else
 gamePid=$(ps -A -o PID,NAME | grep -i 'GAME_PLACEHOLDER$' | head -n 1 | awk '{print $1}')
 if [ -n "$gamePid" ]; then read gameName < "/proc/$gamePid/comm" 2>/dev/null || gameName=''; fi
fi
case "$gamePid" in
 ''|*[!0-9]*) gamePid=''; echo unavailable ;;
 *)
  if [ -r "/proc/$gamePid/stat" ]; then
   echo "PID $gamePid $gameName"
   cat "/proc/$gamePid/stat" 2>/dev/null
   grep -E 'VmRSS:|voluntary_ctxt_switches:|nonvoluntary_ctxt_switches:' "/proc/$gamePid/status" 2>/dev/null
  else
   gamePid=''; echo unavailable
  fi
  ;;
esac
echo FAMILY
if [ -n "$gamePid" ]; then
 gameUid=$(awk '/^Uid:/ {print $2; exit}' "/proc/$gamePid/status" 2>/dev/null)
 case "$gameUid" in ''|*[!0-9]*) ;; *)
 ps -A -o PID,PPID,UID,NAME | while read -r familyPid familyParent familyUid familyName; do
  [ "$familyUid" = "$gameUid" ] || continue
  printf '%s\n' "PF $familyPid $familyParent $familyUid $familyName"
  cat "/proc/$familyPid/stat" 2>/dev/null
  grep '^VmRSS:' "/proc/$familyPid/status" 2>/dev/null
 done
 ;; esac
fi
echo BACKEND
if [ -n "$gamePid" ]; then
 grep -aioE 'dxvk|vkd3d|d3dvk|d8vk|wined3d' "/proc/$gamePid/maps" 2>/dev/null | sort -u
fi
echo THREADS
if [ -n "$gamePid" ]; then
 for commFile in /proc/$gamePid/task/*/comm; do
  read threadName < "$commFile" 2>/dev/null || continue
  case "$threadName" in
   dxvk-*|vkd3d*|d3dvk*|d8vk*|wine_*)
    threadDir=${commFile%/comm}
    echo "TID ${threadDir##*/} $threadName"
    cat "$threadDir/stat" 2>/dev/null
    ;;
  esac
 done
fi
echo BACKGROUND
top -b -n 1 -m 15 -s 5 -o PID,PPID,UID,S,%CPU,NAME 2>/dev/null
echo FEXJIT
tail -n 80 /sdcard/Download/fex-jit.csv 2>/dev/null
'@
$shell=$shell.Replace('GAME_PLACEHOLDER',$GameProcess.ToLowerInvariant()).Replace("`r",'')
while((Get-Date) -lt $until){
 if(-not $surfaceLayer){$surfaceLayer=Get-ActiveGameSurface}
 if($Package -eq 'auto' -and $surfaceLayer -and $surfaceLayer -match 'SurfaceView\[([^/]+)/'){$activePackage=$Matches[1]}
 $frameTime='Waiting for surface updates';$frameRate='Waiting for surface updates';$newFrameCount=0
 $median=$null;$p95=$null;$spike33=0;$spike50=0
 if($surfaceLayer){
  $frameRows=& $adb -s $Serial shell "dumpsys SurfaceFlinger --latency '$surfaceLayer'" 2>$null
  $stamps=@($frameRows | Select-Object -Skip 1 | ForEach-Object {
   if($_ -match '^\d+\s+\d+\s+([1-9]\d+)$'){[long]$Matches[1]}
  } | Sort-Object -Unique)
  $fresh=@($stamps | Where-Object {$_ -gt $lastFrameReady})
  $newFrameCount=$fresh.Count
  $intervals=@();$prior=$lastFrameReady
  foreach($stamp in $fresh){
   if($prior -gt 0){$ms=($stamp-$prior)/1000000.0;if($ms -gt 0 -and $ms -lt 1000){$intervals+=$ms;[void]$timingHistory.Add($ms)}}
   $prior=$stamp
  }
  if($timingHistory.Count -gt 60){$timingHistory.RemoveRange(0,$timingHistory.Count-60)}
  if($fresh.Count -gt 0){$lastFrameReady=$fresh[-1]}
  if($fresh.Count -eq 0){$staleSurfaceSamples++}else{$staleSurfaceSamples=0}
  if($staleSurfaceSamples -ge 3){
   $surfaceLayer=$null;$lastFrameReady=[long]0;$staleSurfaceSamples=0;$timingHistory.Clear()
  }
  if($intervals.Count -ge 10){
   $sorted=@($intervals | Sort-Object)
   $median=$sorted[[int][math]::Floor(($sorted.Count-1)/2)]
   $p95=$sorted[[int][math]::Ceiling(.95*$sorted.Count)-1]
   $spike33=@($intervals | Where-Object {$_ -ge 33.3}).Count
   $spike50=@($intervals | Where-Object {$_ -ge 50.0}).Count
   $frameTime=('{0:N1} ms median; {1:N1} ms p95 ({2} updates)' -f $median,$p95,$intervals.Count)
   $frameRate=('{0:N1} updates/s (not game FPS)' -f (1000/$median))
  }elseif($fresh.Count -gt 0){$frameTime="$($fresh.Count) new updates; warming up"}
 }
 $previousErrorAction=$ErrorActionPreference
 $ErrorActionPreference='Continue'
 $appRead="`necho APPPROFILE`n"
 if($activePackage -match '^[A-Za-z0-9_.]+$' -and $activePackage -ne 'auto'){
  $appRead+="cat /sdcard/Android/data/$activePackage/files/tyrantlator-profile.json 2>/dev/null`necho`n"
 }
 $appRead+="`necho UPTIME`ncat /proc/uptime`n"
 try{$raw=& $adb -s $Serial shell ($shell+$appRead) 2>&1;$adbExit=$LASTEXITCODE}
 finally{$ErrorActionPreference=$previousErrorAction}
 if($adbExit){throw "Live ADB read failed: $($raw -join ' ')"}
 $section='';$cores=@{};$freq=@();$allowedFreq=@();$hardwareFreq=@();$gpu='Unavailable';$gpuValue=$null
 $mem='Unavailable';$memMb=$null;$memTotalMb=$null;$swap='Unavailable';$swapFreeMb=$null;$swapTotalMb=$null
 $swapIn=$null;$swapOut=$null;$swapInRate=$null;$swapOutRate=$null
 $temps=@{cpu=$null;gpu=$null;skin=$null;battery=$null}
 $gameMem='Unavailable';$gameMemMb=$null;$gameCpu='Unavailable';$gameCpuMsPerSec=$null;$ctx='Unavailable';$ctxRate=$null;$gamePid='Unavailable';$gameName='Unavailable';$ticks=$null;$switches=$null
 $wineNow=@{};$winePid=$null;$wineType=$null;$threadNow=@{};$threadId=$null;$threadType=$null
 $jitNow=@{};$backendSeen=@{}
 $backgroundLines=New-Object 'System.Collections.Generic.List[string]'
 $familyLines=New-Object 'System.Collections.Generic.List[string]'
 $appJson='';$deviceElapsedMs=0
 foreach($item in $raw){
  $line="${item}".Trim()
  if($line -in @('CPU','FREQ','LIMIT','GPU','MEM','SWAPIO','THERMAL','WINE','GAME','FAMILY','BACKEND','THREADS','BACKGROUND','FEXJIT','APPPROFILE','UPTIME')){$section=$line;continue}
  switch($section){
   FAMILY {[void]$familyLines.Add($line)}
   BACKGROUND {[void]$backgroundLines.Add($line)}
   APPPROFILE {if($line.StartsWith('{')){$appJson=$line}}
   UPTIME {if($line -match '^([0-9]+(?:\.[0-9]+)?)\s'){$deviceElapsedMs=[double]::Parse($Matches[1],[cultureinfo]::InvariantCulture)*1000}}
   CPU {
    if($line -match '^cpu([0-7])\s+(.+)$'){
     $idx=[int]$Matches[1];$vals=@($Matches[2] -split '\s+' | ForEach-Object {[double]$_})
     if($vals.Count -ge 8){
      $total=0.0;foreach($v in $vals[0..7]){$total+=$v}
      $idle=$vals[3]+$vals[4]
      $busy=$null
      if($previousCpu.ContainsKey($idx)){
       $dt=$total-$previousCpu[$idx].total;$di=$idle-$previousCpu[$idx].idle
       if($dt -gt 0){$busy=[math]::Round(100*($dt-$di)/$dt)}
      }
      $cores[$idx]=$busy;$previousCpu[$idx]=@{total=$total;idle=$idle}
     }
    }
   }
   FREQ {if($line -match '^\d+$'){$freq+=([math]::Round([double]$line/1000))}}
   LIMIT {
    if($line -match '^(\d+)\s+(\d+)$'){
     $allowedFreq+=([math]::Round([double]$Matches[1]/1000))
     $hardwareFreq+=([math]::Round([double]$Matches[2]/1000))
    }
   }
   GPU {
    if($line -match '^(\d+)\s+(\d+)$'){
     $busy=[double]$Matches[1];$total=[double]$Matches[2]
     if($total -gt 0){$gpuValue=100*$busy/$total;$gpu="~$([math]::Round($gpuValue))% (driver busy sample)"}
    }
   }
   MEM {
    if($line -match '^MemTotal:\s+(\d+)'){$memTotalMb=[math]::Round([double]$Matches[1]/1024)}
    if($line -match '^MemAvailable:\s+(\d+)'){$memMb=[math]::Round([double]$Matches[1]/1024);$mem="$memMb MB"}
    if($line -match '^SwapTotal:\s+(\d+)'){$swapTotalMb=[math]::Round([double]$Matches[1]/1024)}
    if($line -match '^SwapFree:\s+(\d+)'){$swapFreeMb=[math]::Round([double]$Matches[1]/1024);$swap="$swapFreeMb MB"}
   }
   SWAPIO {
    if($line -match '^pswpin\s+(\d+)$'){$swapIn=[double]$Matches[1]}
    if($line -match '^pswpout\s+(\d+)$'){$swapOut=[double]$Matches[1]}
   }
   THERMAL {
    if($line -match '^([^ ]+)\s+(\d+)$'){
     $sensor=$Matches[1];$temperature=[double]$Matches[2]/1000
     $kind=if($sensor -like 'cpu-*'){'cpu'}elseif($sensor -like 'gpuss-*'){'gpu'}elseif($sensor -eq 'skin-msm-therm'){'skin'}elseif($sensor -eq 'battery'){'battery'}else{$null}
     if($kind -and ($null -eq $temps[$kind] -or $temperature -gt $temps[$kind])){$temps[$kind]=$temperature}
    }
   }
   WINE {
    if($line -match '^PID (\d+) (.+)$'){
     $winePid=$Matches[1]
     $wineType=if($Matches[2] -match '(?i)wineserver$'){'server'}else{'device'}
    }
    if($winePid -and $line -match '^\d+ \(.+\) [A-Z] (.+)$'){
     $fields=$Matches[1] -split '\s+'
     if($fields.Count -gt 11){$wineNow[$winePid]=@{ticks=([double]$fields[10]+[double]$fields[11]);type=$wineType}}
     $winePid=$null
    }
   }
   GAME {
    if($line -match '^PID (\d+) (.+)$'){$gamePid=$Matches[1];$gameName=$Matches[2]}
    # /proc/<pid>/stat uses 100 CPU ticks per second on this phone.
    if($line -match '^\d+ \(.+\) [A-Z] (.+)$'){
     $fields=$Matches[1] -split '\s+'
     if($fields.Count -gt 11){$ticks=[double]$fields[10]+[double]$fields[11]}
    }
    if($line -match '^VmRSS:\s+(\d+)'){$gameMemMb=[math]::Round([double]$Matches[1]/1024);$gameMem="$gameMemMb MB"}
    if($line -match '^voluntary_ctxt_switches:\s+(\d+)'){$switches=[double]$Matches[1]}
    if($line -match '^nonvoluntary_ctxt_switches:\s+(\d+)' -and $null -ne $switches){$switches += [double]$Matches[1]}
   }
   BACKEND {
    if($line -match '^(?i:dxvk|vkd3d|d3dvk|d8vk|wined3d)$'){$backendSeen[$line.ToUpperInvariant()]=$true}
   }
   THREADS {
    if($line -match '^TID (\d+) (.+)$'){
     $threadId=$Matches[1]
     $name=$Matches[2]
     $threadType=if($name -match '^dxvk-shader-'){'shader'}elseif($name -eq 'dxvk-submit' -or $name -eq 'dxvk-queue'){'submit'}elseif($name -match '^dxvk-'){'dxvkOther'}elseif($name -match '^(vkd3d|d3dvk)'){'vkd3d'}elseif($name -match '^d8vk'){'d8vk'}else{'wineInGame'}
    }
    if($threadId -and $line -match '^\d+ \(.+\) [A-Z] (.+)$'){
     $fields=$Matches[1] -split '\s+'
     if($fields.Count -gt 11){$threadNow[$threadId]=@{ticks=([double]$fields[10]+[double]$fields[11]);type=$threadType}}
     $threadId=$null
    }
   }
   FEXJIT {
    if($line -match '^(\d+),(\d+),(\d+),(\d+)$'){
     $pidKey=$Matches[1]
     $stamp=[double]$Matches[2]
     if(-not $jitNow.ContainsKey($pidKey) -or $stamp -gt $jitNow[$pidKey].stamp){
      $jitNow[$pidKey]=@{stamp=$stamp;cycles=[double]$Matches[3];frequency=[double]$Matches[4]}
     }
    }
   }
  }
 }
 if($gamePid -ne 'Unavailable' -and $gamePid -ne $trackedGamePid){
  $trackedGamePid=$gamePid;$previousBackground=@{};$previousGame=$null;$previousThreads=@{};$previousWine=@{};$gpuRecent.Clear();$allowedBaseline=@{}
  $dashboardHistory.Clear();$dashboardEvents.Clear();$lastEvent=@{};$timingHistory.Clear()
  $median=$null;$p95=$null;$newFrameCount=0;$spike33=0;$spike50=0
  $frameTime='New game detected; warming up';$frameRate='Warming up'
 }
 $appProfile=ConvertFrom-AppProfile -Json $appJson -Package $activePackage -DeviceElapsedMs $deviceElapsedMs
 $now=Get-Date
 $familyElapsed=if($null -ne $previousFamilyAt){($now-$previousFamilyAt).TotalSeconds}else{0}
 $family=ConvertFrom-ProcessFamily -Lines $familyLines.ToArray() -GamePid $gamePid -Previous $previousFamily -ElapsedSeconds $familyElapsed
 $previousFamily=$family.previous;$previousFamilyAt=$now
 $background=ConvertFrom-BackgroundCpu -Lines $backgroundLines.ToArray() -GamePid $gamePid -Package $activePackage -Family $family.rows -Previous $previousBackground -At $now
 $previousBackground=$background.previous
 $cpuPerFrame='Waiting for surface updates';$gameCpuMsPerUpdate=$null;$jitMs=$null
 if($null -ne $swapIn -and $null -ne $swapOut){
  if($previousSwap){
   $swapElapsed=($now-$previousSwap.at).TotalSeconds
   if($swapElapsed -gt 0){
    $swapInRate=[math]::Max(0,($swapIn-$previousSwap['in'])/$swapElapsed)
    $swapOutRate=[math]::Max(0,($swapOut-$previousSwap['out'])/$swapElapsed)
   }
  }
  $previousSwap=@{in=$swapIn;out=$swapOut;at=$now}
 }
 if($null -ne $gpuValue){
  [void]$gpuRecent.Add($gpuValue)
  if($gpuRecent.Count -gt 8){$gpuRecent.RemoveAt(0)}
 }
 $gpuAverage=$null
 if($gpuRecent.Count -gt 0){$gpuAverage=($gpuRecent | Measure-Object -Average).Average}
 $cpuPeak=$null;$busyCoreCount=0
 foreach($coreIndex in $cores.Keys){
  if($null -ne $cores[$coreIndex]){
   if($null -eq $cpuPeak -or $cores[$coreIndex] -gt $cpuPeak){$cpuPeak=$cores[$coreIndex]}
   if($cores[$coreIndex] -ge 90){$busyCoreCount++}
  }
 }
 $policyDrop=0.0;$policyCap=$null
 for($coreIndex=0;$coreIndex -lt $allowedFreq.Count;$coreIndex++){
  if($allowedFreq[$coreIndex] -gt 0){
   if(-not $allowedBaseline.ContainsKey($coreIndex) -or $allowedFreq[$coreIndex] -gt $allowedBaseline[$coreIndex]){$allowedBaseline[$coreIndex]=$allowedFreq[$coreIndex]}
   $drop=100.0*($allowedBaseline[$coreIndex]-$allowedFreq[$coreIndex])/$allowedBaseline[$coreIndex]
   if($drop -gt $policyDrop){$policyDrop=$drop}
   if($coreIndex -eq 6 -and $coreIndex -lt $hardwareFreq.Count -and $hardwareFreq[$coreIndex] -gt 0){$policyCap=100.0*$allowedFreq[$coreIndex]/$hardwareFreq[$coreIndex]}
  }
 }
 $hasWineDelta=$previousWine.Count -gt 0
 $wineServerMs=0.0;$wineDeviceMs=0.0
 foreach($id in $wineNow.Keys){
  if($previousWine.ContainsKey($id)){
   $delta=10*($wineNow[$id].ticks-$previousWine[$id].ticks)
   if($delta -ge 0){if($wineNow[$id].type -eq 'server'){$wineServerMs+=$delta}else{$wineDeviceMs+=$delta}}
  }
 }
 $previousWine=$wineNow
 $hasThreadDelta=$previousThreads.Count -gt 0
 $threadMs=@{shader=0.0;submit=0.0;dxvkOther=0.0;vkd3d=0.0;d8vk=0.0;wineInGame=0.0}
 foreach($id in $threadNow.Keys){
  if($previousThreads.ContainsKey($id)){
   $delta=10*($threadNow[$id].ticks-$previousThreads[$id].ticks)
   if($delta -ge 0){$threadMs[$threadNow[$id].type]+=$delta}
  }
 }
 $previousThreads=$threadNow
 foreach($thread in $threadNow.Values){
  if($thread.type -in @('shader','submit','dxvkOther')){$backendSeen['DXVK']=$true}
  elseif($thread.type -eq 'vkd3d'){$backendSeen['VKD3D']=$true}
  elseif($thread.type -eq 'd8vk'){$backendSeen['D8VK']=$true}
 }
 $backendDisplay=if($backendSeen.Count -gt 0){(@($backendSeen.Keys | Sort-Object) -join ', ')+' indicators'}else{'Unknown; no loaded-library/thread marker'}
 $threadTypes=@($threadNow.Values | ForEach-Object {$_.type})
 $wineHelpers='Waiting for surface updates'
 $dxvkWorkers='No named worker seen';$shaderWorkers='No named worker seen';$submitWorkers='No named worker seen';$vkd3dWorkers='No named worker seen';$d8vkWorkers='No named worker seen';$wineInGameWorkers='No named worker seen'
 if($newFrameCount -gt 0 -and $wineNow.Count -gt 0 -and $hasWineDelta){
  $wineHelpers=('{0:N2} ms/update wineserver; {1:N2} ms/update winedevice' -f ($wineServerMs/$newFrameCount),($wineDeviceMs/$newFrameCount))
 }
 if($newFrameCount -gt 0 -and $threadNow.Count -gt 0 -and $hasThreadDelta){
  if($threadTypes -contains 'shader'){$shaderWorkers=('{0:N2} ms CPU/update (DXVK shader threads)' -f ($threadMs.shader/$newFrameCount))}
  if($threadTypes -contains 'submit'){$submitWorkers=('{0:N2} ms CPU/update (DXVK queue + submit threads)' -f ($threadMs.submit/$newFrameCount))}
  if($threadTypes -contains 'dxvkOther'){$dxvkWorkers=('{0:N2} ms CPU/update (other named DXVK threads)' -f ($threadMs.dxvkOther/$newFrameCount))}
  if($threadTypes -contains 'vkd3d'){$vkd3dWorkers=('{0:N2} ms CPU/update (named VKD3D/D3DVK threads)' -f ($threadMs.vkd3d/$newFrameCount))}
  if($threadTypes -contains 'd8vk'){$d8vkWorkers=('{0:N2} ms CPU/update (named D8VK threads)' -f ($threadMs.d8vk/$newFrameCount))}
  if($threadTypes -contains 'wineInGame'){$wineInGameWorkers=('{0:N2} ms CPU/update (named Wine threads only)' -f ($threadMs.wineInGame/$newFrameCount))}
 }
 if($null -ne $ticks -and $previousGame -and $gamePid -eq $previousGame.pid){
  $elapsed=($now-$previousGame.at).TotalSeconds
  if($elapsed -gt 0){
   $gameCpuMsPerSec=10*($ticks-$previousGame.ticks)/$elapsed
   $gameCpu=('{0:N0} ms/s = {1:N2} core-equivalents' -f $gameCpuMsPerSec,($gameCpuMsPerSec/1000))
   if($newFrameCount -gt 0){$gameCpuMsPerUpdate=10*($ticks-$previousGame.ticks)/$newFrameCount;$cpuPerFrame=('{0:N1} ms CPU/update (entire game process)' -f $gameCpuMsPerUpdate)}
   if($null -ne $switches){$ctxRate=($switches-$previousGame.switches)/$elapsed;$ctx="$([math]::Round($ctxRate)) /s (game main task)"}
  }
 }
 if($null -ne $ticks){$previousGame=@{pid=$gamePid;ticks=$ticks;switches=$switches;at=$now}}
 $jitDisplay='Unavailable for this process (JIT probe not active)'
 $totalJitMs=$null
 if($jitNow.ContainsKey("$gamePid")){
  $sample=$jitNow["$gamePid"]
  if($sample.frequency -gt 0){$totalJitMs=1000*$sample.cycles/$sample.frequency}
  if($previousJit.ContainsKey("$gamePid") -and $sample.stamp -gt $previousJit["$gamePid"].stamp -and $sample.frequency -gt 0){
   $jitMs=1000*($sample.cycles-$previousJit["$gamePid"].cycles)/$sample.frequency
   $jitDisplay=('{0:N2} ms/sample (JIT compile wall time)' -f $jitMs)
  }elseif($sample.frequency -gt 0){
   if($previousJit.ContainsKey("$gamePid")){$jitDisplay=('No new JIT sample; {0:N1} ms total' -f $totalJitMs)}
   else{$jitDisplay=('{0:N1} ms total since game start; awaiting next sample' -f $totalJitMs)}
  }
  $previousJit["$gamePid"]=$sample
 }elseif($gamePid -eq 'Unavailable'){$jitDisplay='Waiting for game process'}
 $recentP95=@($dashboardHistory | Where-Object {$null -ne $_.surface_p95_ms} | Select-Object -Last 30 | ForEach-Object {[double]$_.surface_p95_ms} | Sort-Object)
 $surfaceBaselineMs=$null
 if($recentP95.Count -ge 5){$surfaceBaselineMs=$recentP95[[int][math]::Floor(($recentP95.Count-1)/2)]}
 $surfaceSlowdown=($spike50 -gt 0 -or ($null -ne $p95 -and $p95 -ge [math]::Max(25.0,1.5*$targetMs)))
 if($null -ne $surfaceBaselineMs -and $null -ne $p95 -and $p95 -ge 1.5*$surfaceBaselineMs -and $p95 -ge 1.3*$targetMs){$surfaceSlowdown=$true}
 $assessment='No clear limiter from current sensors';$evidence='Compare a game frame-time spike with these readings.'
 $nextCheck='Watch the game frame graph or FPS overlay while repeating the same scene.'
 if($gamePid -eq 'Unavailable'){$assessment='Waiting for game';$evidence='Start a Windows game in the container to begin diagnosis.';$nextCheck='The dashboard will attach automatically when the game starts.'}
 elseif($null -ne $jitMs -and $jitMs -ge 10){
  $assessment='FEX JIT burst - hitch candidate'
  $evidence=('{0:N1} ms of new code compilation in this sample; confirm against game frame time.' -f $jitMs)
  $nextCheck='Repeat the same movement: a cold-only spike supports JIT compilation.'
 }elseif($null -ne $memMb -and $memMb -lt 1500 -and $null -ne $swapInRate -and $swapInRate -gt 100){
  $assessment='Memory pressure - hitch candidate'
  $evidence=('{0:N0} MB available; {1:N0} swap-in pages/s.' -f $memMb,$swapInRate)
  $nextCheck='Compare the same scene after closing background apps.'
 }elseif($policyDrop -ge 12){
  $assessment='CPU frequency limit fell during session'
  $evidence=('{0:N0}% drop in allowed CPU frequency; heat or power policy may be involved.' -f $policyDrop)
  $nextCheck='Compare cool and warm runs with the same power mode.'
 }elseif($surfaceSlowdown -and $null -ne $gpuAverage -and $gpuRecent.Count -ge 3 -and $gpuAverage -ge 85){
  $assessment='GPU busy during slow surface updates'
  $evidence=('{0:N1} ms surface p95; {1:N0}% recent GPU busy. These coincide, not proven cause.' -f $p95,$gpuAverage)
  $nextCheck='Reduce resolution once and compare game frame time in this scene.'
 }elseif($surfaceSlowdown -and $busyCoreCount -ge 2){
  $assessment='CPU busy during slow surface updates'
  $evidence=('{0:N1} ms surface p95; {1} CPU cores at 90%+.' -f $p95,$busyCoreCount)
  $nextCheck='Capture this scene with Perfetto and inspect the busiest game threads.'
 }elseif($null -ne $gpuValue -and $gpuRecent.Count -ge 3 -and $gpuAverage -ge 85 -and $busyCoreCount -ge 2){
  $assessment='Mixed CPU and GPU pressure'
  $evidence=('{0:N0}% GPU busy average; {1} CPU cores at 90%+.' -f $gpuAverage,$busyCoreCount)
  $nextCheck='Try lower resolution once: a large FPS gain points toward the GPU.'
 }elseif($null -ne $gpuValue -and $gpuRecent.Count -ge 3 -and $gpuAverage -ge 85){
  $assessment='GPU-side pressure if FPS falls'
  $evidence=('{0:N0}% GPU busy average across {1} samples.' -f $gpuAverage,$gpuRecent.Count)
  $nextCheck='Try lower resolution once and compare game frame time in the same scene.'
 }elseif($busyCoreCount -ge 2 -and ($null -eq $gpuAverage -or $gpuAverage -lt 75)){
  $assessment='CPU-side pressure if FPS falls'
  $evidence=("$busyCoreCount CPU cores at 90%+; GPU not equally busy.")
  $nextCheck='Check game-thread scheduling in a Perfetto capture of this scene.'
 }
 if($gamePid -ne 'Unavailable' -and $spike50 -gt 0){
  $detail=('{0} updates above 50 ms; p95 {1:N1} ms; GPU recent {2}; JIT {3}.' -f $spike50,$p95,$(if($null -ne $gpuAverage){'{0:N0}%' -f $gpuAverage}else{'unknown'}),$(if($null -ne $jitMs){'{0:N1} ms' -f $jitMs}else{'unavailable'}))
  Add-ProfileEvent -Kind 'hitch' -Title 'Long surface update' -Detail $detail -At $now
 }elseif($gamePid -ne 'Unavailable' -and $surfaceSlowdown -and $null -ne $surfaceBaselineMs -and $p95 -ge 1.5*$surfaceBaselineMs){
  Add-ProfileEvent -Kind 'slowdown' -Title 'Surface timing worsened' -Detail ('p95 {0:N1} ms versus {1:N1} ms recent baseline.' -f $p95,$surfaceBaselineMs) -At $now
 }
 if($gamePid -ne 'Unavailable'){
  if($null -ne $jitMs -and $jitMs -ge 10){Add-ProfileEvent -Kind 'jit' -Title 'FEX JIT compilation burst' -Detail ('{0:N1} ms new compilation work in this sample.' -f $jitMs) -At $now}
  if($null -ne $memMb -and $memMb -lt 1500 -and $null -ne $swapInRate -and $swapInRate -gt 100){Add-ProfileEvent -Kind 'memory' -Title 'Memory pressure' -Detail ('{0:N0} MB available; {1:N0} swap-in pages/s.' -f $memMb,$swapInRate) -At $now -CooldownSeconds 30}
  if($policyDrop -ge 12){Add-ProfileEvent -Kind 'frequency' -Title 'CPU frequency limit fell' -Detail ('{0:N0}% below the highest limit seen this session.' -f $policyDrop) -At $now -CooldownSeconds 60}
 }
 $swapText=if($null -ne $swapInRate){'{0:N0} in / {1:N0} out pages/s' -f $swapInRate,$swapOutRate}else{'warming up'}
 $thermalText=if($null -ne $temps.cpu){'CPU {0:N1}C; GPU {1:N1}C; skin {2:N1}C; battery {3:N1}C' -f $temps.cpu,$temps.gpu,$temps.skin,$temps.battery}else{'Unavailable'}
 $record=[pscustomobject][ordered]@{
  time=$now.ToString('o');container_package=$activePackage;game_process=$gameName;game_pid=$gamePid;backend_indicators=$backendDisplay;surface_updates=$newFrameCount;surface_median_ms=$median;surface_p95_ms=$p95
  background_cpu_alerts=$background.alerts.Count;app_profile_session=$appProfile.session;app_profile_game=$appProfile.game;app_hud_fps=$appProfile.fps;app_hud_p95_ms=$appProfile.p95_ms;app_profile_status=$appProfile.status
  surface_baseline_ms=$surfaceBaselineMs;surface_slowdown=$surfaceSlowdown;target_fps=$TargetFps
  surface_over_33ms=$spike33;surface_over_50ms=$spike50;game_cpu_ms_per_s=$gameCpuMsPerSec
  gpu_busy_percent=$gpuValue;gpu_busy_recent_avg_percent=$gpuAverage;cpu_peak_busy_percent=$cpuPeak;cpu_cores_over_90_percent=$busyCoreCount
  fex_jit_new_ms=$jitMs;fex_jit_total_ms=$totalJitMs;game_rss_mb=$gameMemMb;mem_available_mb=$memMb
  swap_in_pages_per_s=$swapInRate;swap_out_pages_per_s=$swapOutRate;cpu_max_temp_c=$temps.cpu;gpu_max_temp_c=$temps.gpu;skin_temp_c=$temps.skin
  cpu_allowed_freq_drop_percent=$policyDrop;context_switches_per_s=$ctxRate;assessment=$assessment;evidence=$evidence;next_check=$nextCheck
 }
 $record | Export-Csv -LiteralPath $logPath -NoTypeInformation -Encoding UTF8 -Append
 [void]$dashboardHistory.Add([pscustomobject]@{time=$now.ToString('HH:mm:ss');surface_p95_ms=$p95;surface_median_ms=$median;gpu_busy_percent=$gpuValue;game_cpu_cores=$(if($null -ne $gameCpuMsPerSec){$gameCpuMsPerSec/1000}else{$null});jit_new_ms=$jitMs;surface_spikes_50=$spike50})
 if($dashboardHistory.Count -gt 120){$dashboardHistory.RemoveAt(0)}
 $coreRows=@(for($coreIndex=0;$coreIndex -lt 8;$coreIndex++){
  [pscustomobject]@{index=$coreIndex;busy_percent=$(if($cores.ContainsKey($coreIndex)){$cores[$coreIndex]}else{$null});current_mhz=$(if($coreIndex -lt $freq.Count){$freq[$coreIndex]}else{$null});allowed_mhz=$(if($coreIndex -lt $allowedFreq.Count){$allowedFreq[$coreIndex]}else{$null})}
 })
 $layerRows=@([pscustomobject]@{name='Whole game CPU';value=$cpuPerFrame})
 $layerRows+=([pscustomobject]@{name='Wine helpers';value=$wineHelpers})
 if($backendSeen.ContainsKey('DXVK')){
  $layerRows+=([pscustomobject]@{name='DXVK shader workers';value=$shaderWorkers})
  $layerRows+=([pscustomobject]@{name='DXVK submit workers';value=$submitWorkers})
  $layerRows+=([pscustomobject]@{name='Other DXVK workers';value=$dxvkWorkers})
 }
 if($backendSeen.ContainsKey('VKD3D') -or $backendSeen.ContainsKey('D3DVK')){$layerRows+=([pscustomobject]@{name='VKD3D / D3DVK workers';value=$vkd3dWorkers})}
 if($backendSeen.ContainsKey('D8VK')){$layerRows+=([pscustomobject]@{name='D8VK workers';value=$d8vkWorkers})}
 $layerRows+=([pscustomobject]@{name='Named Wine threads';value=$wineInGameWorkers})
 $layerRows+=([pscustomobject]@{name='FEX JIT compilation';value=$jitDisplay})
 $layerRows+=([pscustomobject]@{name='GPU execution';value='Unavailable: no GPU timer source'})
 $snapshot=[pscustomobject][ordered]@{
  session=$sessionId;generated_at=$now.ToString('o');csv_path=$logPath;target_fps=$TargetFps
  game=$gameName;game_pid=$gamePid;container=$activePackage;backend=$backendDisplay
  app_profile=$appProfile
  process_family=$family.rows
  background_cpu=[pscustomobject]@{status=$background.status;processes=$background.processes;alerts=$background.alerts}
  assessment=$assessment;evidence=$evidence;next_check=$nextCheck
  surface=[pscustomobject]@{median_ms=$median;p95_ms=$p95;baseline_ms=$surfaceBaselineMs;updates=$newFrameCount;spikes_33=$spike33;spikes_50=$spike50;intervals_ms=@($timingHistory.ToArray())}
  cpu=[pscustomobject]@{game_ms_per_s=$gameCpuMsPerSec;game_ms_per_update=$gameCpuMsPerUpdate;peak_busy_percent=$cpuPeak;cores_over_90=$busyCoreCount;policy_drop_percent=$policyDrop;policy_cap_percent=$policyCap;cores=$coreRows;context_switches_per_s=$ctxRate}
  gpu=[pscustomobject]@{busy_percent=$gpuValue;recent_busy_percent=$gpuAverage;frequency_mhz=$null}
  memory=[pscustomobject]@{game_rss_mb=$gameMemMb;available_mb=$memMb;swap_free_mb=$swapFreeMb;swap_in_pages_per_s=$swapInRate;swap_out_pages_per_s=$swapOutRate}
  thermal=[pscustomobject]@{cpu_c=$temps.cpu;gpu_c=$temps.gpu;skin_c=$temps.skin;battery_c=$temps.battery}
  jit=[pscustomobject]@{new_ms=$jitMs;total_ms=$totalJitMs;status=$jitDisplay}
  layers=$layerRows;history=@($dashboardHistory.ToArray());events=@($dashboardEvents.ToArray())
 }
 try{
  $json=$snapshot | ConvertTo-Json -Depth 8 -Compress
  $javascript='window.profileData='+$json+';if(window.renderProfileData){window.renderProfileData(window.profileData);}'
  [System.IO.File]::WriteAllText($DashboardDataPath,$javascript,(New-Object System.Text.UTF8Encoding($false)))
 }catch{Write-Warning "Live browser view could not update: $($_.Exception.Message)"}
 if($Host.Name -eq 'ConsoleHost' -and -not [Console]::IsOutputRedirected){Clear-Host}
 Write-Host 'REDMAGIC / LIVE GAME PROFILE' -ForegroundColor Cyan
 Write-Host "$(Get-Date -Format 'HH:mm:ss')   Container $activePackage   Game $gameName (PID $gamePid)"
 Write-Host ('{0,-32} {1}' -f 'Graphics backend hints',$backendDisplay)
 Write-Host ''
 Write-Host ('{0,-32} {1}' -f 'BOTTLENECK CLUE',$assessment) -ForegroundColor Yellow
 Write-Host ('{0,-32} {1}' -f 'Why',$evidence)
 Write-Host ('{0,-32} {1}' -f 'Next check',$nextCheck)
 Write-Host 'Pressure clue only; confirm against a game frame-time graph or FPS overlay.' -ForegroundColor DarkGray
 Write-Host ''
 Write-Host ('{0,-32} {1}' -f 'Compositor update interval',$frameTime)
 Write-Host ('{0,-32} {1}' -f 'Compositor update rate',$frameRate)
 Write-Host ('{0,-32} {1}' -f 'Surface spikes',"$spike33 over 33 ms; $spike50 over 50 ms (this sample)")
 Show-TimingGraph
 Write-Host ''
 Write-Host ('{0,-32} {1}' -f 'Whole-game CPU work',$cpuPerFrame)
 Write-Host ('{0,-32} {1}' -f 'Wine helper CPU work',$wineHelpers)
 if($backendSeen.ContainsKey('DXVK')){
  Write-Host ('{0,-32} {1}' -f 'DXVK shader CPU work',$shaderWorkers)
  Write-Host ('{0,-32} {1}' -f 'DXVK submit CPU work',$submitWorkers)
  Write-Host ('{0,-32} {1}' -f 'Other DXVK thread CPU work',$dxvkWorkers)
 }
 if($backendSeen.ContainsKey('VKD3D') -or $backendSeen.ContainsKey('D3DVK')){Write-Host ('{0,-32} {1}' -f 'VKD3D / D3DVK CPU work',$vkd3dWorkers)}
 if($backendSeen.ContainsKey('D8VK')){Write-Host ('{0,-32} {1}' -f 'D8VK CPU work',$d8vkWorkers)}
 if($backendSeen.Count -eq 0){Write-Host ('{0,-32} {1}' -f 'Translation worker CPU','No backend marker exposed')}
 Write-Host ('{0,-32} {1}' -f 'Named in-game Wine CPU work',$wineInGameWorkers)
 Write-Host ('{0,-32} {1}' -f 'FEX JIT compilation',$jitDisplay)
 Write-Host 'Exact game/FEX/Wine/DXVK/VKD3D/Turnip layer ms and GPU execution ms: unavailable.' -ForegroundColor DarkGray
 Write-Host 'Named worker CPU rows are partial and overlap whole-game CPU work.' -ForegroundColor DarkGray
 Write-Host ''
 Write-Host ('{0,-32} {1}' -f 'Game process CPU use',$gameCpu)
 Write-Host ('{0,-32} {1}' -f 'GPU utilization',("$gpu; recent " + $(if($null -ne $gpuAverage){'{0:N0}% ({1} valid)' -f $gpuAverage,$gpuRecent.Count}else{'unavailable'})))
 Write-Host ('{0,-32} {1}' -f 'GPU frequency','Unavailable (device denies access)')
 Write-Host ('{0,-32} {1}' -f 'Memory use',"Game RSS $gameMem; available $mem; swap free $swap")
 Write-Host ('{0,-32} {1}' -f 'Swap activity',$swapText)
 Write-Host ('{0,-32} {1}' -f 'Temperatures',$thermalText)
 Write-Host ('{0,-32} {1}' -f 'CPU policy frequency',$(if($null -ne $policyCap){'{0:N0}% of hardware max on core 6; {1:N0}% drop this run' -f $policyCap,$policyDrop}else{'Unavailable'}))
 Write-Host ('{0,-32} {1}' -f 'Shader compilation events','Unavailable; use the active backend HUD/log if provided')
 Write-Host ('{0,-32} {1}' -f 'Context switches',$ctx)
 Write-Host ('{0,-32} {1}' -f 'Scheduling','Detailed timeline in saved Perfetto trace')
 Write-Host ''
 Write-Host 'CPU per core: busy% / current MHz / allowed MHz'
 for($i=0;$i -lt 8;$i+=2){
  $pair=@()
  foreach($coreIndex in @($i,($i+1))){
   $usage=if($cores.ContainsKey($coreIndex) -and $null -ne $cores[$coreIndex]){"$($cores[$coreIndex])%"}else{'...'}
   $mhz=if($coreIndex -lt $freq.Count -and $freq[$coreIndex]){$freq[$coreIndex]}else{'?'}
   $limit=if($coreIndex -lt $allowedFreq.Count){$allowedFreq[$coreIndex]}else{'?'}
   $pair+=('C{0}: {1,4} / {2,4} / {3,4}' -f $coreIndex,$usage,$mhz,$limit)
  }
  Write-Host ($pair -join '     ')
 }
 Write-Host ''
 Write-Host 'Surface updates are not game frames. JIT compile work is not total FEX overhead.' -ForegroundColor Yellow
 Write-Host "Session log: $logPath"
 Write-Host 'Press Ctrl+C to stop.'
 Start-Sleep -Seconds 1
}


