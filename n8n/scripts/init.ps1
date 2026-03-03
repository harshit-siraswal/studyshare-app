Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$n8nDir = Resolve-Path (Join-Path $scriptDir "..")
$envPath = Join-Path $n8nDir ".env"
$examplePath = Join-Path $n8nDir ".env.example"

if (-not (Test-Path $examplePath)) {
  throw "Missing .env.example at $examplePath"
}

if (-not (Test-Path $envPath)) {
  Copy-Item $examplePath $envPath
  Write-Output "Created .env from .env.example"
} else {
  Write-Output ".env already exists; existing secrets will be preserved."
}

function New-HexSecret([int]$bytes) {
  $buffer = New-Object byte[] $bytes
  $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
  try {
    $rng.GetBytes($buffer)
  } finally {
    $rng.Dispose()
  }
  return ([BitConverter]::ToString($buffer)).Replace("-", "").ToLowerInvariant()
}

function Normalize-EnvValue {
  param([string]$Value)
  if ($null -eq $Value) { return $null }
  $v = $Value.Trim()
  if ($v.Length -lt 2) { return $v }

  $first = $v[0]
  $last = $v[$v.Length - 1]
  if (($first -eq '"' -and $last -eq '"') -or ($first -eq "'" -and $last -eq "'")) {
    $v = $v.Substring(1, $v.Length - 2)
    if ($first -eq '"') {
      $v = $v.Replace('\"', '"')
    } else {
      $v = $v.Replace("\'", "'")
    }
    $v = $v.Replace('\\', '\')
  }
  return $v
}

function Set-EnvVar {
  param(
    [string]$Path,
    [string]$Name,
    [string]$Value
  )
  $content = Get-Content -Path $Path -Raw
  $escapedName = [Regex]::Escape($Name)
  $linePattern = "(?m)^$escapedName=.*$"
  if ([Regex]::IsMatch($content, $linePattern)) {
    $replacementLine = "$Name=$Value"
    $content = [Regex]::Replace(
      $content,
      $linePattern,
      [System.Text.RegularExpressions.MatchEvaluator]{
        param($match)
        return $replacementLine
      }
    )
  } else {
    if (-not $content.EndsWith("`n")) {
      $content += "`n"
    }
    $content += "$Name=$Value`n"
  }
  [System.IO.File]::WriteAllText($Path, $content, [System.Text.UTF8Encoding]::new($false))
}

function Get-EnvVar {
  param(
    [string]$Path,
    [string]$Name
  )
  $line = Select-String -Path $Path -Pattern "^$([Regex]::Escape($Name))=" | Select-Object -First 1
  if ($null -eq $line) { return $null }
  return (Normalize-EnvValue (($line.Line -split "=", 2)[1]))
}

function Should-ReplaceSecret {
  param([string]$Value)
  if ([string]::IsNullOrWhiteSpace($Value)) { return $true }
  $v = $Value.Trim().ToLowerInvariant()
  return (
    $v.StartsWith("replace") -or
    $v.StartsWith("change") -or
    $v.StartsWith("example")
  )
}

$updated = @()
$preserved = @()

$enc = Get-EnvVar -Path $envPath -Name "N8N_ENCRYPTION_KEY"
if (Should-ReplaceSecret -Value $enc) {
  Set-EnvVar -Path $envPath -Name "N8N_ENCRYPTION_KEY" -Value (New-HexSecret 32)
  $updated += "N8N_ENCRYPTION_KEY"
} else {
  $preserved += "N8N_ENCRYPTION_KEY"
}

$basic = Get-EnvVar -Path $envPath -Name "N8N_BASIC_AUTH_PASSWORD"
if (Should-ReplaceSecret -Value $basic) {
  Set-EnvVar -Path $envPath -Name "N8N_BASIC_AUTH_PASSWORD" -Value (New-HexSecret 18)
  $updated += "N8N_BASIC_AUTH_PASSWORD"
} else {
  $preserved += "N8N_BASIC_AUTH_PASSWORD"
}

$db = Get-EnvVar -Path $envPath -Name "POSTGRES_PASSWORD"
if (Should-ReplaceSecret -Value $db) {
  Set-EnvVar -Path $envPath -Name "POSTGRES_PASSWORD" -Value (New-HexSecret 18)
  $updated += "POSTGRES_PASSWORD"
} else {
  $preserved += "POSTGRES_PASSWORD"
}

if ($updated.Count -gt 0) {
  Write-Output ("Updated: " + ($updated -join ", "))
} else {
  Write-Output "No placeholder secrets found; no secret values changed."
}
if ($preserved.Count -gt 0) {
  Write-Output ("Preserved: " + ($preserved -join ", "))
}
Write-Output "Run ./scripts/up.ps1 next."
