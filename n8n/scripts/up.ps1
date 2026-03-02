Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$n8nDir = Resolve-Path (Join-Path $scriptDir "..")
$envPath = Join-Path $n8nDir ".env"

if (-not (Test-Path $envPath)) {
  Write-Output ".env not found; running init script first."
  & (Join-Path $scriptDir "init.ps1")
}

$envMap = @{}
foreach ($line in Get-Content $envPath) {
  if ([string]::IsNullOrWhiteSpace($line)) { continue }
  if ($line.TrimStart().StartsWith("#")) { continue }
  $idx = $line.IndexOf("=")
  if ($idx -lt 1) { continue }
  $key = $line.Substring(0, $idx).Trim()
  $val = $line.Substring($idx + 1).Trim()
  $envMap[$key] = $val
}

if ($envMap.ContainsKey("N8N_DATA_ROOT") -and -not [string]::IsNullOrWhiteSpace($envMap["N8N_DATA_ROOT"])) {
  $root = $envMap["N8N_DATA_ROOT"]
  foreach ($dir in @("n8n_data", "postgres", "redis")) {
    $path = Join-Path $root $dir
    if (-not (Test-Path $path)) {
      New-Item -Path $path -ItemType Directory | Out-Null
    }
  }
}

Push-Location $n8nDir
try {
  docker compose --env-file .env up -d
  docker compose --env-file .env ps
} finally {
  Pop-Location
}

Write-Output "n8n should be available at http://localhost:5678 (unless you changed .env)."
