$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot
$out = Join-Path $project 'dist/windows'
New-Item -Type Directory -Path $out -Force | Out-Null
$csc = Join-Path $env:windir 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
$sources = @(Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.cs' | ForEach-Object FullName)
& $csc /nologo /optimize+ /target:winexe /codepage:65001 "/out:$out/iRemote.Receiver.exe" /reference:System.Security.dll @sources
if ($LASTEXITCODE -ne 0) { throw 'Falló la compilación del receptor.' }
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Start-iRemote.ps1') -Destination $out
