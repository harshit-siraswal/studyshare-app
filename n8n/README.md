# Self-hosted n8n (Docker)

This stack runs:
- `n8n` main API/editor service
- `n8n-worker` for queue executions
- `postgres` for durable state
- `redis` for queue transport

## Prerequisites

- Docker Desktop running
- Docker Compose available

## Quick start (PowerShell)

From repository root:

```powershell
cd n8n
./scripts/init.ps1
./scripts/up.ps1
```

Open:
- `http://localhost:5678`

Use credentials from `n8n/.env`:
- `N8N_BASIC_AUTH_USER`
- `N8N_BASIC_AUTH_PASSWORD`

Data is stored on host path configured by `N8N_DATA_ROOT` (default: `D:/DockerData/mystudyspace-n8n`).

## Day-to-day operations

```powershell
cd n8n
./scripts/logs.ps1 -Follow
./scripts/logs.ps1 -Service n8n -Follow
./scripts/backup.ps1
./scripts/down.ps1
```

## Production checklist

- Configure HTTPS and set:
  - `N8N_PROTOCOL=https`
  - `N8N_HOST=<your-domain>`
  - `WEBHOOK_URL=https://<your-domain>/`
  - `N8N_EDITOR_BASE_URL=https://<your-domain>`
  - `N8N_SECURE_COOKIE=true`
- Keep `.env` private.
- Rotate `N8N_ENCRYPTION_KEY`, basic auth password, and DB password periodically.
- Keep image on a recent `stable` release.
