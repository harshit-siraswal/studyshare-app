# 02 - Cloudflare DNS Setup

## A. Open DNS records

1. Go to `https://dash.cloudflare.com`
2. Click your zone: `studyshare.in`
3. Left menu: **DNS**
4. Click **Records**

## B. Create origin host (DNS-only)

1. Click **Add record**
2. Type: **A**
3. Name: `origin-api`
4. IPv4 address: `EC2_PUBLIC_IP`
5. Proxy status: **DNS only** (gray cloud)
6. TTL: Auto
7. Click **Save**

## C. Create public API host (proxied)

1. Click **Add record**
2. Type: **CNAME**
3. Name: `api`
4. Target: `origin-api.studyshare.in`
5. Proxy status: **Proxied** (orange cloud)
6. TTL: Auto
7. Click **Save**

## D. Remove stale records (if present)

1. Search for any `api.mystudyspace.me` references in these locations and remove/update them:
   - Cloudflare DNS records search bar
   - Cloudflare zone settings
   - Deployment config files (Vercel/Netlify/GitHub Actions/Terraform)
   - Environment variables/secrets
   - Repository docs/source files

Do not use `api.mystudyspace.me` in production.
2. In `studyshare.in` zone, remove/repoint stale backend records such as:
- CNAMEs targeting Render hosts (for example `*.onrender.com` or `*.render.com`)
- A records pointing to old Render-assigned IPs
3. Ensure each remaining API/web record points to the current active backend target.

## E. Validate DNS resolution

Run locally:

```powershell
Resolve-DnsName api.studyshare.in
Resolve-DnsName origin-api.studyshare.in
```

Cross-platform alternatives:

```bash
nslookup api.studyshare.in
nslookup origin-api.studyshare.in
dig +short api.studyshare.in
dig +short origin-api.studyshare.in
```

Expected results:

- `api.studyshare.in` should resolve to Cloudflare IPs (or Cloudflare-managed proxied CNAME targets), not your origin server IP. This is expected for proxied A/AAAA/CNAME records.
- `origin-api.studyshare.in` resolves to EC2 public IP (DNS-only A record).

Note: DNS propagation may take 1-5 minutes. Re-run checks after a short wait if values look stale.
