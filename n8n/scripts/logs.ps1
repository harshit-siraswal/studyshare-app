param(
  [string]$Service = "",
  [switch]$Follow
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$n8nDir = Resolve-Path (Join-Path $scriptDir "..")

$argsList = @("compose", "logs")
if ($Follow) {
  $argsList += "-f"
}
if ($Service) {
  $argsList += $Service
}

Push-Location $n8nDir
try {
  docker @argsList
} finally {
  Pop-Location
}
