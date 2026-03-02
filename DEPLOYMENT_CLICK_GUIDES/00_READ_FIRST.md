# StudySpace Production Rollout (Read First)

Follow these files in exact order:

1. `01_EC2_Backend_Deploy.md`
2. `02_Cloudflare_DNS_Setup.md`
3. `03_Cloudflare_Worker_Setup.md`
4. `04_Vercel_Admin_Dashboard.md`
5. `05_Vercel_Web_App.md`
6. `06_Verification_Checklist.md`

Do not skip steps.

## Required values before you start

- `EC2_PUBLIC_IP` (example: `13.48.57.16`)
- `EC2_SSH_USER` (example: `ubuntu`)
- `EC2_KEY_PATH` (path to your `.pem`)
- `BACKEND_PATH_ON_EC2` (example: `/home/ubuntu/studyspace-backend`)
- `ORIGIN_HOST` (example: `origin-api.example.com`)
- `PUBLIC_API_HOST` (example: `api.example.com`)
- `ADMIN_HOST` (example: `admin.example.com`)
- `WEB_HOST` (example: `www.example.com`)

Use your own production domains for all placeholders above.

## Important architecture (best practice)

- Public API users hit: `https://api.example.com`
- Cloudflare Worker route handles: `api.example.com/*`
- Worker forwards to origin host: `https://origin-api.example.com` (DNS-only, not proxied)
- Keep the origin DNS record DNS-only so Cloudflare does not proxy and expose origin routing unexpectedly; additionally restrict origin access to Cloudflare IP ranges (or use Cloudflare Authenticated Origin Pull) so direct origin traffic is blocked.
- EC2/Nginx serves origin backend

## Prerequisite checks (before cutover)

- Confirm DNS records are present and correct: required `A`/`CNAME` records and any TXT verification records.
- Confirm Cloudflare Worker is deployed, route is attached, and worker health endpoint responds.
- Confirm EC2 health: SSH reachable, service status healthy (app + Nginx), disk/memory/CPU in safe range, and outbound network connectivity works.
- Confirm Nginx serves backend locally on expected ports and reverse proxy routes are active.
- Confirm SSL certs are valid: expiry date, chain validity, and SAN hostnames match public/origin hosts.
- Confirm security groups and host firewall allow only intended traffic.
- Confirm database connectivity/credentials and recent backup snapshot availability.
- Confirm dependent services/APIs (email, storage, auth, push) are reachable.

## Rollback procedure (high-level)

- Trigger rollback when SLO thresholds are breached (for example: sustained `>1%` 5xx, severe latency regression, or repeated health-check failures).
- Revert Cloudflare route to previous worker/origin mapping.
- Repoint DNS to previous known-good target if route rollback is not sufficient.
- Revert or mitigate database migration effects before traffic restore (or apply backward-compatible fallback migration).
- Restore previous Nginx config or known-good EC2 snapshot/AMI.
- Notify stakeholders/on-call/status channel during rollback execution.
- Target rollback RTO should be pre-agreed and tracked during incident handling.
- Verify traffic and health endpoints after rollback before reopening access.
- Detailed operator runbook: `01_EC2_Backend_Deploy.md` section **F. Rollback procedure (if deployment fails)**.

## Security checklist

- Enforce TLS on all public endpoints and verify certificate chain.
- Keep origin DNS as DNS-only and restrict origin access to Cloudflare.
- Verify auth/ACL protections for admin and privileged APIs.
- Confirm CORS policy allows only approved origins/methods/headers (explicitly list allowed values).
- Verify rate limiting and DDoS protections are enabled at edge and origin.
- Verify secrets are managed securely (no hardcoded credentials, rotation policy, secure secret store).
- Verify security headers are present (`HSTS`, `CSP`, `X-Frame-Options`, `Referrer-Policy`).
- Verify logging for security events (auth failures, suspicious requests, blocked origin access).

## Monitoring and troubleshooting

- Cloudflare: check Worker logs, route errors, and edge status codes.
- EC2/Nginx: check app logs, Nginx error/access logs, and service status.
- Dashboards/metrics: monitor latency, error rate, saturation (CPU/memory), and request volume on your primary observability dashboard.
- Probe health endpoints at public API and origin API with explicit pass criteria (`200` and healthy dependency status).
- Alert thresholds: for example `>1%` 5xx sustained or `>10 errors/min` on critical routes.
- Incident response: follow on-call escalation path and notify stakeholders/status page as defined in your incident process.
