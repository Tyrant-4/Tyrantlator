# Shared parser for the optional Tyrantlator HUD export. Never treats old or foreign data as live.
function ConvertFrom-AppProfile {
 param([string]$Json,[string]$Package,[double]$DeviceElapsedMs)
 $result=[pscustomobject]@{status='Unavailable: enable per-game profiling in a custom build';session=$null;game=$null;container_id=$null;display_backend=$null;fps=$null;p95_ms=$null;intervals_ms=@()}
 if(-not $Json){return $result}
 try {
  $data=$Json | ConvertFrom-Json -ErrorAction Stop
  if($data.schema -ne 1 -or $data.package -ne $Package -or $data.source -ne 'app_hud_present_intervals' -or -not $data.session){throw 'Invalid identity'}
  $exportElapsedMs=[double]$data.elapsed_ms
  if($null -eq $data.elapsed_ms -or [double]::IsNaN($exportElapsedMs) -or [double]::IsInfinity($exportElapsedMs) -or $exportElapsedMs -lt 0 -or [double]::IsNaN($DeviceElapsedMs) -or [double]::IsInfinity($DeviceElapsedMs) -or $DeviceElapsedMs -le 0){throw 'Invalid clock'}
  $age=$DeviceElapsedMs-$exportElapsedMs
  if($age -lt -1000 -or $age -gt 5000){$result.status='Stale app export';return $result}
  $result.session=$data.session;$result.game=$data.game;$result.container_id=$data.container_id;$result.display_backend=$data.display_backend
  if($data.status -eq 'stopped'){$result.status='App profiling session ended';return $result}
  if($data.status -eq 'idle'){$result.status='No recent app frame (idle or unbound window)';return $result}
  $frameAgeMs=[double]$data.frame_age_ms
  if($data.status -ne 'active' -or $null -eq $data.frame_age_ms -or [double]::IsNaN($frameAgeMs) -or [double]::IsInfinity($frameAgeMs) -or $frameAgeMs -lt 0 -or $frameAgeMs+$age -gt 1500){$result.status='No recent app frame';return $result}
  $fps=[double]$data.fps
  if($null -eq $data.fps -or [double]::IsNaN($fps) -or [double]::IsInfinity($fps) -or $fps -lt 0){throw 'Invalid FPS'}
  $values=@($data.intervals_ms)
  if($values.Count -gt 120){throw 'Oversized frame history'}
  foreach($value in $values){if($null -eq $value -or [double]::IsNaN([double]$value) -or [double]::IsInfinity([double]$value) -or [double]$value -le 0 -or [double]$value -ge 10000){throw 'Invalid interval'}}
  $result.fps=$fps;$result.intervals_ms=@($values | ForEach-Object {[double]$_})
  if($values.Count -ge 2){$sorted=@($result.intervals_ms | Sort-Object);$result.p95_ms=$sorted[[int][math]::Round(0.95*($sorted.Count-1))]}
  $result.status='Live app presents (millisecond clock; latest 120 intervals)'
 } catch {$result.status='Invalid app export; waiting for a valid snapshot'}
 return $result
}
