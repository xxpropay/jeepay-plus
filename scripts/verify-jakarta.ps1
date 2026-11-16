$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$modules = @(
    'jeepay-core',
    'jeepay-service',
    'jeepay-components',
    'jeepay-manager',
    'jeepay-merchant',
    'jeepay-payment'
) | ForEach-Object { Join-Path $root $_ }

$hits = & rg -n 'import javax\.(servlet|validation|annotation|jms|websocket)' @modules --glob '*.java'
if ($LASTEXITCODE -eq 0) {
    throw "Legacy Java EE imports remain:`n$($hits -join "`n")"
}

Write-Host 'Jakarta import verification passed.'
