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

function Normalize-EnvValue {
  param([string]$Value)
  if ($null -eq $Value) { return $null }
  $v = $Value.Trim()
  if ($v.Length -ge 2) {
    $first = $v[0]
    $last = $v[$v.Length - 1]
    if (($first -eq '"' -and $last -eq '"') -or ($first -eq "'" -and $last -eq "'")) {
      $v = $v.Substring(1, $v.Length - 2)
      if ($first -eq '"') {
        $v = $v.Replace('\"', '"').Replace('\\', '\')
      } else {
        $v = $v.Replace("\'", "'").Replace('\\', '\')
      }
    }
  }
  return $v
}

$envMap = @{}
foreach ($line in Get-Content $envPath) {
  if ([string]::IsNullOrWhiteSpace($line)) { continue }
  if ($line.TrimStart().StartsWith("#")) { continue }
  $idx = $line.IndexOf("=")
  if ($idx -lt 1) { continue }
  $key = $line.Substring(0, $idx).Trim()
  $val = Normalize-EnvValue ($line.Substring($idx + 1))
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
  $dump = docker compose --env-file .env exec -T postgres pg_dump -U "$($envMap["POSTGRES_USER"])" -d "$($envMap["POSTGRES_DB"])" 2>&1
  $pgDumpExit = $LASTEXITCODE
  $dumpText = if ($dump -is [System.Array]) { ($dump -join [Environment]::NewLine) } else { [string]$dump }
  if ($pgDumpExit -ne 0 -or [string]::IsNullOrWhiteSpace($dumpText)) {
    throw "pg_dump failed (exit=$pgDumpExit). Output: $dumpText"
  }
  [System.IO.File]::WriteAllText($dbOut, "$dumpText`n", [System.Text.UTF8Encoding]::new($false))

  docker compose --env-file .env exec -T n8n n8n export:workflow --all --pretty --output=/tmp/workflows.json | Out-Null
  if ($LASTEXITCODE -eq 0) {
    docker compose --env-file .env cp n8n:/tmp/workflows.json $wfOut | Out-Null
    $copyExit = $LASTEXITCODE
    if ($copyExit -ne 0 -or -not (Test-Path $wfOut)) {
      throw "Failed to copy workflows export from container (exit=$copyExit)."
    }
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
