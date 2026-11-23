param([switch]$Background)
$ErrorActionPreference = 'Stop'
$exe = Join-Path $PSScriptRoot 'iRemote.Receiver.exe'
if (-not (Test-Path -LiteralPath $exe)) { throw 'Ejecuta windows/Build.ps1 y abre el lanzador de dist/windows.' }
$directory = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'iRemote'
New-Item -ItemType Directory -Path $directory -Force | Out-Null
$stamp = Join-Path $directory 'certificate.txt'
$certificate = $null
if (Test-Path -LiteralPath $stamp) {
    $id = (Get-Content -LiteralPath $stamp -Raw).Trim()
    if ($id -match '^[0-9a-fA-F]{40}$') {
        $certificate = Get-Item -LiteralPath "Cert:/CurrentUser/My/$id" -ErrorAction SilentlyContinue
    }
}
if (-not $certificate -or -not $certificate.HasPrivateKey -or $certificate.NotAfter -lt (Get-Date)) {
    $certificate = New-SelfSignedCertificate -Subject 'CN=iRemote Receiver' -CertStoreLocation 'Cert:/CurrentUser/My' `
        -Type SSLServerAuthentication -KeyAlgorithm RSA -KeyLength 3072 -HashAlgorithm SHA256 `
        -KeyExportPolicy NonExportable -NotAfter (Get-Date).AddYears(3)
    Set-Content -LiteralPath $stamp -Value $certificate.Thumbprint -Encoding Ascii
}
$launchArguments = @($certificate.Thumbprint)
if ($Background) {
    $launchArguments += '--background'
    Start-Process -FilePath $exe -ArgumentList $launchArguments -WindowStyle Hidden
} else {
    Start-Process -FilePath $exe -ArgumentList $launchArguments -WindowStyle Normal
}
