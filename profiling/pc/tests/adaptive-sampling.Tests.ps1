$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../scripts/adaptive-sampling.ps1')
$at=[datetime]'2026-10-06T10:00:00';$state=New-AdaptiveSamplingState
$first=Get-AdaptiveSamplePlan $state $at
if(-not $first.thermal -or -not $first.family -or -not $first.background){throw 'First sample not complete'}
foreach($key in $state.Keys.Clone()){$state[$key]=$at}
$early=Get-AdaptiveSamplePlan $state $at.AddSeconds(2)
if($early.thermal -or $early.family -or $early.background){throw 'Slow sources polled too early'}
$due=Get-AdaptiveSamplePlan $state $at.AddSeconds(3)
if(-not $due.thermal -or -not $due.family -or -not $due.background){throw 'Slow source never refreshed'}
$state.family=$at.AddSeconds(3)
$split=Get-AdaptiveSamplePlan $state $at.AddSeconds(4)
if($split.family -or -not $split.background){throw 'Independent source clocks lost'}
'PASS: initial reads, skipped slow checks, independent freshness and refresh deadline'
