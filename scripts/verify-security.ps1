$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$scopes = @('jeepay-core','jeepay-service','jeepay-components','jeepay-manager','jeepay-merchant','jeepay-payment') |
    ForEach-Object { Join-Path $root $_ }

$prints = & rg -n 'printStackTrace\(' @scopes
if ($LASTEXITCODE -eq 0) { throw "printStackTrace remains:`n$prints" }

$weakLogs = & rg -n 'log\.error\(e\.getMessage\(\)\)' @scopes
if ($LASTEXITCODE -eq 0) { throw "Stack trace is discarded:`n$weakLogs" }

Write-Host 'Security verification passed.'
