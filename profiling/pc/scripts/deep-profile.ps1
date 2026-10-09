# PowerShell 7. Extends the existing Perfetto capture; does not launch or stop a game.
param(
 [switch]$Capture,
 [string]$RunDir='',
 [ValidatePattern('^[A-Za-z0-9_.-]+$')][string]$GameProcess='ACOrigins.exe',
 [ValidatePattern('^[A-Za-z0-9_.]+$')][string]$Package='com.tencent.ig',
 [ValidateRange(3,120)][int]$Seconds=20,
 [ValidatePattern('^[A-Za-z0-9]+$')][string]$Serial='9126023101C5',
 [string]$ProjectRoot=(Split-Path $PSScriptRoot -Parent),
 [string]$DashboardDataPath=''
)
$ErrorActionPreference='Stop'
if($Capture){
 $captureRoot=Join-Path $ProjectRoot ('work/deep-profiles/'+[guid]::NewGuid().ToString('N'))
 & (Join-Path $PSScriptRoot 'profile-redmagic.ps1') -Action Capture -Seconds $Seconds -Package $Package -Serial $Serial -ProjectRoot $ProjectRoot -OutputRoot $captureRoot
 $RunDir=(Get-ChildItem $captureRoot -Directory | Select-Object -First 1).FullName
}
if(-not $RunDir){throw 'Provide -RunDir for an existing trace, or -Capture for a new recording.'}
$trace=Join-Path $RunDir 'trace.pftrace'
if(-not (Test-Path $trace)){throw "No trace at $trace"}
$sql=(Get-Content (Join-Path $PSScriptRoot 'deep-profile.sql') -Raw).Replace('GAME_NAME',$GameProcess)
$queryPath=Join-Path $RunDir 'deep-query.sql'
[IO.File]::WriteAllText($queryPath,$sql,[Text.UTF8Encoding]::new($false))
$info=[Diagnostics.ProcessStartInfo]::new((Join-Path $ProjectRoot 'tools/perfetto/trace_processor_shell.exe'))
foreach($arg in @('query','-f',$queryPath,$trace)){$info.ArgumentList.Add($arg)}
$info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true;$info.UseShellExecute=$false
$process=[Diagnostics.Process]::Start($info)
$stderr=$process.StandardError.ReadToEndAsync()
$stdout=$process.StandardOutput.ReadToEnd()
$process.WaitForExit()
$diagnostics=$stderr.GetAwaiter().GetResult()
$diagnostics | Set-Content (Join-Path $RunDir 'deep-query-diagnostics.txt')
if($process.ExitCode){throw "Trace analysis failed: $diagnostics"}
# Perfetto prints a single JSON cell enclosed in quotes (not RFC 4180 escaped CSV).
$line=@($stdout -split '\r?\n' | Where-Object {$_.StartsWith('"{') -or $_.StartsWith('{')})
if($line.Count -ne 1){throw 'Trace processor did not return exactly one JSON result.'}
$json=$line[0]
if($json.StartsWith('"')){$json=$json.Substring(1,$json.Length-2)}
$report=$json | ConvertFrom-Json
$status=if($report.scheduler_slices -eq 0){'Unavailable: scheduler data was not captured'}elseif($null -eq $report.game){"Game process not found in trace: $GameProcess"}elseif($report.data_loss_events -gt 0){'Partial capture: trace reports data loss'}else{'Captured CPU scheduling; historical sample'}
$report | Add-Member -NotePropertyName status -NotePropertyValue $status
$report | Add-Member -NotePropertyName game_process -NotePropertyValue $GameProcess
$report | Add-Member -NotePropertyName analyzed_at -NotePropertyValue ([DateTimeOffset]::Now.ToString('o'))
$report | Add-Member -NotePropertyName trace_path -NotePropertyValue ([IO.Path]::GetFullPath($trace))
$report | Add-Member -NotePropertyName trace_modified_at -NotePropertyValue ((Get-Item $trace).LastWriteTimeUtc.ToString('o'))
$report | Add-Member -NotePropertyName package -NotePropertyValue $Package
$resultJson=$report | ConvertTo-Json -Depth 10
$resultJson | Set-Content (Join-Path $RunDir 'deep-profile.json') -Encoding utf8NoBOM
$report.threads | Export-Csv (Join-Path $RunDir 'deep-threads.csv') -NoTypeInformation
if(-not $DashboardDataPath){$DashboardDataPath=Join-Path $ProjectRoot 'deep-profile-data.js'}
$DashboardDataPath=[IO.Path]::GetFullPath($DashboardDataPath)
New-Item -ItemType Directory -Force (Split-Path $DashboardDataPath -Parent) | Out-Null
[IO.File]::WriteAllText($DashboardDataPath+'.tmp',"window.deepProfileData=$resultJson;if(window.renderDeepProfile){window.renderDeepProfile(window.deepProfileData);}",[Text.UTF8Encoding]::new($false))
Move-Item -LiteralPath ($DashboardDataPath+'.tmp') -Destination $DashboardDataPath -Force
Write-Host $status
if($report.game){Write-Host ("Game CPU: {0} core equivalents across {1:N1}s; PID {2}" -f $report.game.cpu_cores,$report.duration_s,$report.game.pid)}
$report.threads | Format-Table tid,name,cpu_percent,runnable_ms,p95_wait_ms -AutoSize
Write-Host "Saved: $(Join-Path $RunDir 'deep-profile.json')"
