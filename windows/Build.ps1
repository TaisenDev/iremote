param([string]$OutputDirectory)
$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot
$dist = Join-Path $project 'dist'
$out = if ($OutputDirectory) { [IO.Path]::GetFullPath($OutputDirectory) } else { Join-Path $dist 'windows' }
New-Item -Type Directory -Path $dist -Force | Out-Null
New-Item -Type Directory -Path $out -Force | Out-Null
$csc = Join-Path $env:windir 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
$qrPackage = Join-Path $project 'dist/qrcoder.1.6.0.nupkg'
if (-not (Test-Path -LiteralPath $qrPackage)) {
    Invoke-WebRequest -UseBasicParsing -Uri 'https://api.nuget.org/v3-flatcontainer/qrcoder/1.6.0/qrcoder.1.6.0.nupkg' -OutFile $qrPackage
}
$qrHash = (Get-FileHash -LiteralPath $qrPackage -Algorithm SHA256).Hash
if ($qrHash -ne 'D84BFFE9DECF1FA2B8755610407959F998209029C3B6B95A1B282CEB9983A36F') {
    throw 'QRCoder no coincide con el SHA-256 fijado.'
}
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [IO.Compression.ZipFile]::OpenRead($qrPackage)
$qrDll = Join-Path $out 'QRCoder.dll'
try { [IO.Compression.ZipFileExtensions]::ExtractToFile($archive.GetEntry('lib/net40/QRCoder.dll'), $qrDll, $true) }
finally { $archive.Dispose() }
$sources = @(Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.cs' | ForEach-Object FullName)
$icon = Join-Path $PSScriptRoot 'iRemote.ico'
& $csc /nologo /optimize+ /target:winexe /codepage:65001 "/out:$out/iRemote.Receiver.exe" "/win32icon:$icon" /reference:System.Security.dll "/reference:$qrDll" @sources
if ($LASTEXITCODE -ne 0) { throw 'Falló la compilación del receptor.' }
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Start-iRemote.ps1') -Destination $out
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'QRCoder.LICENSE.txt') -Destination $out
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Enable-PrivateLan.ps1') -Destination $out
