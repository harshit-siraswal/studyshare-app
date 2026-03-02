# 01 - EC2 Backend Deploy

## A. Connect to EC2

1. Open **PowerShell**.
2. If SSH reports `UNPROTECTED PRIVATE KEY FILE`, run this first from **elevated PowerShell**:

```powershell
icacls "EC2_KEY_PATH" /inheritance:r /grant:r "$($env:USERNAME):R"
```

This restricts key access to your current user.
3. Run:

```powershell
ssh -i "EC2_KEY_PATH" EC2_SSH_USER@EC2_PUBLIC_IP
```

## B. Pull latest backend code

1. Run:

```bash
cd BACKEND_PATH_ON_EC2
git rev-parse --abbrev-ref HEAD
git status --porcelain
if [ -n "$(git status --porcelain)" ]; then
  echo "Repository has uncommitted changes. Stash or commit before deploy."
  exit 1
fi
# If you need to continue with local changes, run one of these first:
# 1) stash: git stash save "pre-deploy-$(date +%Y%m%d-%H%M%S)"
# 2) commit: git add . && git commit -m "Pre-deploy commit"
git fetch origin
git log HEAD..origin/<branch>
git tag -a "deploy-$(date +%Y%m%d-%H%M%S)" -m "pre-deploy"
git pull origin <branch>
```

2. Ensure `<branch>` is your intended deploy branch (`main`/`production`).

## C. Update backend environment

1. Run (backup first, then edit):

```bash
cp .env .env.backup.$(date +%Y%m%d-%H%M%S)
nano .env
```

2. Ensure these values exist (or update):

```env
NODE_ENV=production
PORT=3001
TRUST_PROXY=1
FRONTEND_URL=https://studyshare.in
CORS_ALLOWED_ORIGINS=https://www.studyshare.in,https://studyshare.in,https://admin-studyspace.vercel.app,https://admin.studyshare.in
```

3. This is not exhaustive. Also verify all required variables for your stack (database credentials, JWT/secret keys, API keys, email/SMS credentials, storage keys, and other service-specific config from your app config or `.env.example`).

4. Save in nano:
- Press `Ctrl+O`
- Press `Enter`
- Press `Ctrl+X`

5. Validate `.env` before continuing:

```bash
test -s .env || { echo ".env is empty"; exit 1; }
grep -nE '^[A-Za-z_][A-Za-z0-9_]*=.*$' .env | head
# Example "critical" keys (adjust this list to your app's actual env schema):
grep -E '^(NODE_ENV|PORT|TRUST_PROXY|FRONTEND_URL|CORS_ALLOWED_ORIGINS)=' .env
```

If your repo includes an env validator script, run it (for example `npm run validate:env`).

## D. Build and restart backend

Use one path only, based on your setup.

### If using Docker Compose

1. Run:

```bash
docker compose down
docker compose up -d --build
docker compose ps
```

### If using PM2

1. Run:

```bash
npm ci
npm run build || { echo "Build failed - aborting deploy"; exit 1; }
pm2 list
pm2 reload <process-name>
pm2 status
```

2. Use `pm2 list`/`pm2 status` to find the backend process name before reload. If env vars do not refresh, run `pm2 delete <process-name>` and start it again with your normal PM2 start command.

## E. Confirm backend health

1. Internal health check from EC2:

```bash
curl -i http://localhost:3001/health
```

2. Confirm response includes `HTTP/1.1 200`.

If internal check fails, troubleshoot before external checks:

```bash
pm2 logs <process-name>
pm2 status
docker compose logs
docker compose ps
lsof -i :3001
netstat -tulpn | grep 3001
```

Also re-check `.env` values and startup config.

3. External health check from outside EC2:

```bash
curl -i https://<YOUR_API_HOST>/health
```

4. If internal passes but external fails, verify Security Group inbound rules, NACLs, and load balancer/listener target registration.

Before running AWS CLI checks, confirm your AWS CLI credentials and region are configured (`aws configure` / `aws sts get-caller-identity`):

```bash
aws ec2 describe-security-groups --group-ids <SECURITY_GROUP_ID>
aws elbv2 describe-target-health --target-group-arn <TARGET_GROUP_ARN>
aws elbv2 describe-listeners --load-balancer-arn <LOAD_BALANCER_ARN>
```

Use these outputs to confirm service-port ingress, target health state (`healthy`), and listener protocol/port mapping.

## F. Rollback procedure (if deployment fails)

1. Revert code to previous commit:

```bash
git log --oneline
# WARNING: git reset --hard permanently discards uncommitted changes.
# Stash or commit local work first (for example: git stash).
git reset --hard PREVIOUS_COMMIT_HASH
```

2. Restore backed-up environment:

```bash
ls -lt .env.backup.*
cp .env.backup.<SELECTED_TIMESTAMP> .env
```

3. Rebuild/restart based on runtime:

```bash
# Docker Compose
docker compose down
docker compose up -d --build
```

```bash
# PM2
npm ci
npm run build
pm2 restart <process-name>
```

4. Re-run health verification from section **E** (`curl -i http://localhost:3001/health` and external check).
