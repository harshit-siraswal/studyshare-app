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
# Edit only the value assigned to `DEPLOY_BRANCH` below (for example: `main` or `production`).
DEPLOY_BRANCH=
if [ -z "$DEPLOY_BRANCH" ]; then
  echo "DEPLOY_BRANCH is not set - please set it to your deploy branch"
  exit 1
fi
if [ -n "$(git status --porcelain)" ]; then
  echo "Repository has uncommitted changes. Stash or commit before deploy."
  exit 1
fi
# If you need to continue with local changes, run one of these first:
# 1) stash: git stash save "pre-deploy-$(date +%Y%m%d-%H%M%S)"
# 2) commit: git add . && git commit -m "Pre-deploy commit"
git fetch origin
git log HEAD..origin/"$DEPLOY_BRANCH"
git log --stat HEAD..origin/"$DEPLOY_BRANCH"
# Optional but recommended per commit:
# git show <commit_sha>
# git show --pretty=fuller --show-signature <commit_sha>
# git verify-commit <commit_sha>
read -r -p "Proceed with pull from origin/$DEPLOY_BRANCH? Type yes to continue: " confirm_pull
if [ "$confirm_pull" != "yes" ]; then
  echo "Deployment aborted by operator before pull."
  exit 1
fi
git tag -a "deploy-$(date +%Y%m%d-%H%M%S)" -m "pre-deploy"
git pull origin "$DEPLOY_BRANCH"
```

2. `git pull` must run only after incoming commits are reviewed and confirmed (or signatures are verified).

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
FRONTEND_URL=https://mystudyspace.in
CORS_ALLOWED_ORIGINS=https://www.mystudyspace.in,https://mystudyspace.in,https://admin-studyspace.vercel.app,https://admin.mystudyspace.in
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
for i in 1 2 3 4 5; do
  if [ -z "$(docker compose ps -q)" ]; then
    break
  fi
  echo "Waiting for containers to stop... (attempt $i/5)"
  sleep 2
done
if [ -n "$(docker compose ps -q)" ]; then
  echo "Containers are still running after docker compose down; aborting deploy."
  docker compose ps
  exit 1
fi
df -h .
# Abort if available space on current filesystem is below 2GB (adjust threshold as needed):
if [ "$(df -Pk . | awk 'NR==2 {print $4}')" -lt 2097152 ]; then
  echo "Low disk space (<2GB). Clean up unused Docker images/containers/caches before deploy."
  echo "Examples: docker image prune -a, docker container prune, docker volume prune, npm cache clean --force"
  exit 1
fi
docker compose up -d --build
docker compose ps
```

### If using PM2

1. Run:

```bash
npm ci
df -h .
# Abort if available space on current filesystem is below 2GB (adjust threshold as needed):
if [ "$(df -Pk . | awk 'NR==2 {print $4}')" -lt 2097152 ]; then
  echo "Low disk space (<2GB). Clean up build caches/artifacts before deploy."
  echo "Examples: npm cache clean --force, rm -rf node_modules/.cache, remove old build artifacts"
  exit 1
fi
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
pm2 logs <process-name> --lines 50
pm2 status
docker compose logs --tail=50
docker compose ps
# lsof/netstat may be missing on minimal distros; use ss as default:
ss -ltnp | grep 3001
# Optional legacy tools (may require install/sudo):
lsof -i :3001
netstat -tulpn | grep 3001
```

Also re-check `.env` values and startup config.

3. External health check from outside EC2:

```bash
curl -i https://<YOUR_API_HOST>/health
```

4. Immediately verify recent application logs after external health check:

```bash
# PM2 runtime
pm2 status
pm2 logs <process-name> --lines 50

# Docker runtime
docker compose ps
docker compose logs --tail=50 <service-name>
```

Use the exact process name from `pm2 status` and the exact compose service name from `docker compose ps` to correlate a successful `/health` response with any runtime warnings/errors.

5. If internal passes but external fails, verify Security Group inbound rules, NACLs, and load balancer/listener target registration.

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


