Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$n8nDir = Resolve-Path (Join-Path $scriptDir "..")
$exitCode = 1

Push-Location $n8nDir
try {
  docker compose down
  $exitCode = $LASTEXITCODE
} finally {
  Pop-Location
}

exit $exitCode
