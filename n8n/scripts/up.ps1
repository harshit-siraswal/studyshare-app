Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$n8nDir = Resolve-Path (Join-Path $scriptDir "..")
$envPath = Join-Path $n8nDir ".env"

if (-not (Test-Path $envPath)) {
  Write-Output ".env not found; running init script first."
  & (Join-Path $scriptDir "init.ps1")
  if (-not (Test-Path $envPath)) {
    Write-Error ".env is still missing after init. Aborting startup."
    exit 1
  }
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

if ($envMap.ContainsKey("N8N_DATA_ROOT") -and -not [string]::IsNullOrWhiteSpace($envMap["N8N_DATA_ROOT"])) {
  $root = $envMap["N8N_DATA_ROOT"]
  if (-not (Test-Path $root)) {
    New-Item -Path $root -ItemType Directory -Force | Out-Null
  }
  foreach ($dir in @("n8n_data", "postgres", "redis")) {
    $path = Join-Path $root $dir
    if (-not (Test-Path $path)) {
      New-Item -Path $path -ItemType Directory -Force | Out-Null
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

$resolvedPort = $null
if ($envMap.ContainsKey("N8N_PORT") -and -not [string]::IsNullOrWhiteSpace($envMap["N8N_PORT"])) {
  $resolvedPort = $envMap["N8N_PORT"]
} elseif ($envMap.ContainsKey("PORT") -and -not [string]::IsNullOrWhiteSpace($envMap["PORT"])) {
  $resolvedPort = $envMap["PORT"]
} else {
  $resolvedPort = "5678"
}

Write-Output "n8n should be available at http://localhost:$resolvedPort (unless you changed host/bind settings in .env)."
