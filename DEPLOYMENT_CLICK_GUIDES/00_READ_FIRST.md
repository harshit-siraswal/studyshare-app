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
- Keep the origin DNS record DNS-only so Cloudflare does not proxy origin routing unexpectedly.
- Restrict origin access to Cloudflare IP ranges (or enable Cloudflare Authenticated Origin Pull) so direct origin traffic is blocked.
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
- Post-deployment smoke test plan is prepared and executable immediately after cutover:
  - Hit public and worker health endpoints (`https://api.../health`, worker route health) and expect `200` with healthy dependency payloads.
  - Exercise critical user flows: login + one API read/write path that touches DB; expect success without auth/5xx errors.
  - Validate Nginx reverse-proxy routing and full SSL chain from an external client; expect valid cert chain and correct backend upstream.
  - Validate external dependencies with simple test calls (email, storage, auth); expect successful responses within normal latency.
  - Run a lightweight synthetic smoke request burst (for example 20-50 curl/HTTP checks over 2-5 minutes) and confirm stable success rate/latency while serving real traffic.
  - If any smoke step fails, halt rollout, alert on-call, and execute rollback/mitigation immediately.

## Rollback procedure (high-level)

- Trigger rollback when SLO thresholds are breached (example value: sustained `>1%` 5xx; actual SLO targets must be defined per service/team), severe latency regression, or repeated health-check failures.
- Revert Cloudflare route to previous worker/origin mapping.
- Repoint DNS to previous known-good target if route rollback is not sufficient.
- Revert or mitigate database migration effects before traffic restore (or apply backward-compatible fallback migration).
- Restore previous Nginx config or known-good EC2 snapshot/AMI.
- Notify stakeholders/on-call/status channel during rollback execution.
- Target rollback RTO should be pre-agreed and tracked during incident handling.
- Verify traffic and health endpoints after rollback before reopening access.
- Detailed operator runbook: `01_EC2_Backend_Deploy.md` section **F. Rollback procedure (if deployment fails)**.

### Gradual rollout and mitigation

- Prefer canary and percentage-based shifts before full cutover (for example 5% -> 25% -> 50% -> 100%).
- Use feature flags to disable risky code paths without full deploy reversion when possible.
- Use progressive rollback before full reversion when partial mitigation works (for example 100% -> 50% -> 10% -> 0%).
- Stack mechanisms:
  - Cloudflare Worker route version swap/rollback.
  - DNS or traffic shifting between known-good and candidate targets.
  - Load balancer target-group weight changes for gradual traffic steering.
- Automatic rollback/mitigation triggers should include sustained 5xx increase, latency regression vs baseline, and health-check failures.
- Recommended monitoring windows:
  - Canary: 15-30 minutes minimum before increasing traffic.
  - Mid-stage (25-50%): 30-60 minutes minimum.
  - Full-stage: monitor continuously for at least 60 minutes after final shift.
- Escalation: page on-call immediately on trigger breach; escalate to service owner/incident channel if breach persists beyond 10 minutes.
- Operator steps reference: `01_EC2_Backend_Deploy.md` section **F**.

## Security checklist

- Enforce TLS on all public endpoints and verify certificate chain.
- Keep origin DNS as DNS-only and restrict origin access to Cloudflare.
- Verify auth/ACL protections for admin and privileged APIs.
- Confirm CORS policy allows only approved origins/methods/headers (explicitly list allowed values).
  - Example origins allowlist (replace with your own domains): `https://example.com, https://www.example.com, https://admin.example.com, https://admin-dashboard.example.com`
  - Example methods allowlist: `GET, POST, PUT, PATCH, DELETE, OPTIONS`
  - Example headers allowlist: `Authorization, Content-Type, X-Requested-With`
- Verify rate limiting and DDoS protections are enabled at edge and origin.
- Verify secrets are managed securely (no hardcoded credentials, rotation policy, secure secret store).
- Verify security headers are present (`HSTS`, `CSP`, `X-Frame-Options`, `Referrer-Policy`).
- Verify logging for security events (auth failures, suspicious requests, blocked origin access).

## Monitoring and troubleshooting

- Cloudflare: check Worker logs, route errors, and edge status codes.
- EC2/Nginx: check app logs, Nginx error/access logs, and service status.
- Dashboards/metrics: monitor latency, error rate, saturation (CPU/memory), and request volume on your primary observability dashboard.
- Probe health endpoints at public API and origin API with explicit pass criteria (`200` and healthy dependency status).
- Alert thresholds (illustrative examples only): `>1%` 5xx sustained or `>10 errors/min` on critical routes; production thresholds must be tuned to each service baseline/SLO.
- Incident response: follow on-call escalation path and notify stakeholders/status page as defined in your incident process.
