param([string]$ShellPath='')
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
if(-not $ShellPath){$ShellPath=Join-Path $root 'tools/llvm-mingw-20260922-ucrt-x86_64/busybox/bin/sh.exe'}
if(-not (Test-Path $ShellPath)){throw 'Provide -ShellPath with a local POSIX shell for this check.'}
$source=[IO.File]::ReadAllText((Join-Path $root 'scripts/live-redmagic.ps1'))
$template=[regex]::Match($source,'(?s)\$shell=@''\r?\n(.*?)\r?\n''@').Groups[1].Value.Replace("`r",'')
if(-not $template){throw 'Collector shell template missing'}
$shell=$template.Replace('THERMAL_DUE','0').Replace('FAMILY_DUE','0').Replace('BACKGROUND_DUE','0').Replace('CACHED_GAME_PID','100').Replace('GAME_PLACEHOLDER','auto').Replace('SCHEDULER_SAMPLE_PLACEHOLDER',':')
$out=Join-Path $root 'work/profile-check/adaptive-shell-test.sh'
New-Item -ItemType Directory -Force (Split-Path $out) | Out-Null
[IO.File]::WriteAllText($out,$shell,(New-Object Text.UTF8Encoding($false)))
& $ShellPath -n $out
if($LASTEXITCODE -ne 0){throw 'Phone shell syntax failed'}
$sections=([regex]::Match($shell,'(?s)echo THERMAL\n(.*?)echo GAME').Groups[1].Value)+([regex]::Match($shell,'(?s)echo FAMILY\n(.*?)echo BACKEND').Groups[1].Value)+([regex]::Match($shell,'(?s)echo BACKGROUND\n(.*?)echo FEXJIT').Groups[1].Value)
# Run the actual collector guards against harmless command stubs.
$stubs="top() { echo TOP_CALLED; }`nps() { :; }`nawk() { echo 1000; }`ncat() { :; }`ngrep() { :; }`n"
foreach($id in @('100','101')){
 [IO.File]::WriteAllText($out,("gamePid=$id`n"+$stubs+$sections),(New-Object Text.UTF8Encoding($false)))
 $result=(& $ShellPath $out) -join "`n"
 if($id -eq '100' -and $result -match 'SAMPLED_|TOP_CALLED'){throw 'Skipped slow probes executed'}
 if($id -eq '101' -and ($result -notmatch 'SAMPLED_FAMILY' -or $result -notmatch 'TOP_CALLED')){throw 'Game change failed to force refresh'}
}
'PASS: shell syntax, skipped slow probes and forced process refresh after game change'
