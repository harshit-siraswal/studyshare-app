#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PS_SCRIPT="$SCRIPT_DIR/up.ps1"

if [ ! -f "$PS_SCRIPT" ]; then
  echo "up.ps1 not found at $PS_SCRIPT" >&2
  exit 1
fi

if [ ! -r "$PS_SCRIPT" ]; then
  echo "up.ps1 is not readable at $PS_SCRIPT" >&2
  exit 1
fi

if command -v pwsh >/dev/null 2>&1; then
  pwsh -NoProfile -ExecutionPolicy Bypass -File "$PS_SCRIPT"
elif command -v powershell >/dev/null 2>&1; then
  powershell -NoProfile -ExecutionPolicy Bypass -File "$PS_SCRIPT"
else
  echo "PowerShell is required to run $PS_SCRIPT (install pwsh or powershell)." >&2
  exit 1
fi
