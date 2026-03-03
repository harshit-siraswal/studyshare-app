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

### Alternative: Bash/Shell

```bash
cd n8n
./scripts/init.sh
./scripts/up.sh
```

Open:
- `http://localhost:5678`

Use credentials from `n8n/.env`:
- `N8N_BASIC_AUTH_USER`
- `N8N_BASIC_AUTH_PASSWORD`
- `INTERNAL_API_KEY` (must match backend `INTERNAL_API_KEY` for `/api/internal/ocr/*` calls)

`INTERNAL_API_KEY` setup for `/api/internal/ocr/*`:
- Here, "backend" means the API service that exposes `/api/internal/ocr/*` (not n8n itself).
- Set `INTERNAL_API_KEY` in that backend service environment/config.
- Set the same value in every internal caller (n8n/worker/cron) that sends requests to `/api/internal/ocr/*`.
- Restart backend and caller services after changing this key.

Data is stored on host path configured by `N8N_DATA_ROOT` (example: `/path/to/n8n-data`).

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
  - `N8N_SECURE_COOKIE=true` (enable only when traffic is actually HTTPS end-to-end)
- HTTPS implementation guidance:
  - Terminate TLS at a reverse proxy/load balancer (for example Nginx, Traefik, or cloud LB).
  - Obtain and renew certificates (Let's Encrypt/certbot, or Traefik ACME automation).
  - In Docker Compose deployments, expose ports `80/443` on the proxy container and keep `WEBHOOK_URL` + `N8N_EDITOR_BASE_URL` aligned to externally reachable HTTPS hostnames.
- Secrets handling requirements:
  - Never commit `.env` to version control; keep `.env` in `.gitignore`.
  - Keep a scrubbed `.env.example` for defaults/templates only.
  - On servers, restrict permissions for `.env` (for example `chmod 600 .env`).
  - Prefer runtime secret injection (AWS Secrets Manager, Vault, Azure Key Vault, Docker/Kubernetes secrets) over plaintext files when possible.
  - Use CI/CD secret stores for build/deploy pipelines; do not echo secrets in logs.
  - Rotate basic auth and DB credentials regularly; store backups securely and audit secret access.
  - Use tools such as `git-secrets` to detect accidental secret commits.
  - `INTERNAL_API_KEY`:
    - Generate a strong secret (minimum 32 random bytes; hex/base64 via a secure generator or secrets manager).
    - Rotate periodically and immediately on suspected compromise; use staged rollout (accept old+new briefly, then revoke old).
    - Inject via secure secret stores (Vault/KMS/Secrets Manager/Kubernetes Secrets/platform env injection), not hardcoded files.
    - If compromised: revoke key, rotate all callers, review `/api/internal/ocr/*` access logs, and tighten source IP/service scope.
- `N8N_ENCRYPTION_KEY` warning:
  - Do not rotate `N8N_ENCRYPTION_KEY` after initial setup unless you are prepared to lose encrypted credentials/data.
  - Safe key rotation requires export/decrypt/re-encrypt migration planning before switching keys.
  - Continue rotating basic auth and DB passwords, but treat `N8N_ENCRYPTION_KEY` as long-lived.
- Keep image on a recent `stable` release.
