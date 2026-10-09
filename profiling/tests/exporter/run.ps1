param([Parameter(Mandatory)][string]$JavaHome, [Parameter(Mandatory)][string]$JsonJar,
      [Parameter(Mandatory)][string]$OutputDirectory)
$ErrorActionPreference='Stop'
$repo=Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
$sources=@((Join-Path $repo 'app/src/main/java/com/winlator/star/perf/ProfileExporter.java'),
           (Join-Path $repo 'app/src/main/java/com/winlator/star/widget/FpsCounter.java'),
           (Join-Path $PSScriptRoot 'ExporterLifecycleCheck.java'))
$sources+=@(Get-ChildItem (Join-Path $PSScriptRoot 'stubs') -Recurse -Filter '*.java' | ForEach-Object FullName)
New-Item -ItemType Directory -Force $OutputDirectory | Out-Null
& (Join-Path $JavaHome 'bin/javac.exe') -encoding UTF-8 -cp $JsonJar -d $OutputDirectory $sources
if($LASTEXITCODE){throw 'Exporter test compilation failed'}
& (Join-Path $JavaHome 'bin/java.exe') -cp ($OutputDirectory+';'+$JsonJar) ExporterLifecycleCheck
if($LASTEXITCODE){throw 'Exporter lifecycle test failed'}
