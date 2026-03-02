Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$n8nDir = Resolve-Path (Join-Path $scriptDir "..")
$envPath = Join-Path $n8nDir ".env"
$backupDir = Join-Path $n8nDir "backups"

if (-not (Test-Path $envPath)) {
  throw "Missing .env at $envPath. Run ./scripts/init.ps1 first."
}

if (-not (Test-Path $backupDir)) {
  New-Item -Path $backupDir -ItemType Directory | Out-Null
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

if (-not $envMap.ContainsKey("POSTGRES_USER") -or -not $envMap.ContainsKey("POSTGRES_DB")) {
  throw "POSTGRES_USER or POSTGRES_DB missing in .env."
}

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$dbOut = Join-Path $backupDir "n8n_db_$timestamp.sql"
$wfOut = Join-Path $backupDir "n8n_workflows_$timestamp.json"

Push-Location $n8nDir
try {
  $dump = docker compose --env-file .env exec -T postgres pg_dump -U $envMap["POSTGRES_USER"] -d $envMap["POSTGRES_DB"]
  [System.IO.File]::WriteAllLines($dbOut, $dump, [System.Text.UTF8Encoding]::new($false))

  docker compose --env-file .env exec -T n8n n8n export:workflow --all --pretty --output=/tmp/workflows.json | Out-Null
  if ($LASTEXITCODE -eq 0) {
    docker compose --env-file .env cp n8n:/tmp/workflows.json $wfOut | Out-Null
    docker compose --env-file .env exec -T n8n sh -lc "rm -f /tmp/workflows.json" | Out-Null
  } else {
    # Fresh instances can return non-zero when no workflows exist yet.
    [System.IO.File]::WriteAllText($wfOut, "[]`n", [System.Text.UTF8Encoding]::new($false))
  }
} finally {
  Pop-Location
}

Write-Output "Backup created:"
Write-Output "  $dbOut"
Write-Output "  $wfOut"
