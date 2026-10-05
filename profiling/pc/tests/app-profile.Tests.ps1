$ErrorActionPreference='Stop'
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts/read-app-profile.ps1')
function Assert-True($Condition,$Message){if(-not $Condition){throw $Message}}
$sample=[ordered]@{schema=1;session='test-session';package='com.tencent.ig';game='Test game';container_id=3;display_backend='vulkan';source='app_hud_present_intervals';status='active';elapsed_ms=10000;frame_age_ms=10;fps=60;intervals_ms=@(16,17,18,50)}
function Read-Sample {ConvertFrom-AppProfile -Json ($sample | ConvertTo-Json -Compress) -Package 'com.tencent.ig' -DeviceElapsedMs 10100}
$data=Read-Sample
Assert-True ($data.fps -eq 60 -and $data.p95_ms -eq 50 -and $data.intervals_ms.Count -eq 4) 'Valid live data was lost'
$sample.package='com.other.app';$data=Read-Sample
Assert-True ($null -eq $data.fps -and $data.intervals_ms.Count -eq 0) 'Foreign app data accepted'
$sample.package='com.tencent.ig';$sample.elapsed_ms=100;$data=Read-Sample
Assert-True ($data.status -eq 'Stale app export' -and $null -eq $data.fps) 'Old export accepted'
$sample.elapsed_ms=10000;$sample.status='stopped';$data=Read-Sample
Assert-True ($null -eq $data.fps -and $data.status -match 'ended') 'Stopped session accepted'
$sample.status='idle';$data=Read-Sample
Assert-True ($null -eq $data.fps -and $data.intervals_ms.Count -eq 0) 'Idle frame history accepted'
$sample.status='active';$sample.frame_age_ms=1490;$data=Read-Sample
Assert-True ($null -eq $data.fps) 'Old frame accepted despite fresh export'
$sample.frame_age_ms=10;$sample.intervals_ms=@(0,16);$data=Read-Sample
Assert-True ($null -eq $data.fps) 'Invalid interval accepted'
$sample.intervals_ms=@(16,17)
foreach($invalidClock in @('NaN','Infinity',-1)) {
 $sample.elapsed_ms=$invalidClock;$data=Read-Sample
 Assert-True ($null -eq $data.fps) 'Invalid export clock accepted'
}
$sample.elapsed_ms=10000
foreach($invalidClock in @('NaN','Infinity',-1)) {
 $sample.frame_age_ms=$invalidClock;$data=Read-Sample
 Assert-True ($null -eq $data.fps) 'Invalid frame clock accepted'
}
$sample.frame_age_ms=10
$data=ConvertFrom-AppProfile -Json ($sample | ConvertTo-Json -Compress) -Package 'com.tencent.ig' -DeviceElapsedMs ([double]::NaN)
Assert-True ($null -eq $data.fps) 'Invalid device clock accepted'
$sample.intervals_ms=@(1..121);$data=Read-Sample
Assert-True ($null -eq $data.fps) 'Oversized history accepted'
$data=ConvertFrom-AppProfile -Json '{broken' -Package 'com.tencent.ig' -DeviceElapsedMs 10100
Assert-True ($null -eq $data.fps) 'Broken JSON accepted'
$data=ConvertFrom-AppProfile -Json '' -Package 'com.tencent.ig' -DeviceElapsedMs 10100
Assert-True ($data.status -match 'Unavailable') 'Existing app without exporter should still work'
'PASS: live, foreign, stale, stopped, idle, old-frame, invalid, oversized, broken and missing exports'
