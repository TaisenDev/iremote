# Run as administrator, from the final installation directory.
$ErrorActionPreference = 'Stop'
$exe = Join-Path $PSScriptRoot 'iRemote.Receiver.exe'
if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { throw 'Falta iRemote.Receiver.exe en esta carpeta.' }
$path = (Resolve-Path -LiteralPath $exe).ProviderPath
$ports = '28251-28255'
foreach ($protocol in 'TCP','UDP') {
    $name = "iRemote-PrivateLan-$protocol"
    $existing = Get-NetFirewallRule -Name $name -ErrorAction SilentlyContinue
    if ($existing) {
        $existing | Set-NetFirewallRule -Profile Private -Direction Inbound -Action Allow -Enabled True `
            -EdgeTraversalPolicy Block -RemoteAddress LocalSubnet -Protocol $protocol -LocalPort $ports -Program $path
    } else {
        New-NetFirewallRule -Name $name -DisplayName "iRemote (red privada, $protocol)" `
            -Profile Private -Direction Inbound -Action Allow -EdgeTraversalPolicy Block -RemoteAddress LocalSubnet `
            -Protocol $protocol -LocalPort $ports -Program $path | Out-Null
    }
}
