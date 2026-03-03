# 02 - Cloudflare DNS Setup

Replace `YOUR_DOMAIN.com` with your real domain before executing steps.

## A. Open DNS records

1. Go to `https://dash.cloudflare.com`
2. Click your zone: `YOUR_DOMAIN.com`
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
4. Target: `origin-api.YOUR_DOMAIN.com`
5. Proxy status: **Proxied** (orange cloud)
6. TTL: Auto
7. Click **Save**

## D. Remove stale records (if present)

- [ ] Search for stale domain references (example: `old-api.example`) in Cloudflare DNS records and remove/update them.
- [ ] Search for stale domain references (example: `old-api.example`) in Cloudflare zone settings and remove/update them.
- [ ] Search for stale domain references (example: `old-api.example`) in deployment config files (Vercel/Netlify/GitHub Actions/Terraform) and remove/update them.
- [ ] Search for stale domain references (example: `old-api.example`) in environment variables/secrets and remove/update them.
- [ ] Search for stale domain references (example: `old-api.example`) in repository docs/source files and remove/update them.

Do not leave stale domain references (for example `old-api.example`) in production.
- [ ] In `YOUR_DOMAIN.com` zone, remove/repoint stale backend CNAMEs targeting old hosts (for example `*.onrender.com` or `*.render.com`).
- [ ] In `YOUR_DOMAIN.com` zone, remove/repoint stale backend A records pointing to old IPs.
- [ ] Ensure each remaining API/web record points to the current active backend target.

## E. Validate DNS resolution

Run locally:

```powershell
Resolve-DnsName api.YOUR_DOMAIN.com
Resolve-DnsName origin-api.YOUR_DOMAIN.com
```

Cross-platform alternatives:

```bash
nslookup api.YOUR_DOMAIN.com
nslookup origin-api.YOUR_DOMAIN.com
dig +short api.YOUR_DOMAIN.com
dig +short origin-api.YOUR_DOMAIN.com
```

Expected results:

- `api.YOUR_DOMAIN.com` should resolve to Cloudflare IPs (or Cloudflare-managed proxied CNAME targets), not your origin server IP. This is expected for proxied A/AAAA/CNAME records.
- `origin-api.YOUR_DOMAIN.com` resolves to EC2 public IP (DNS-only A record).

Example output patterns:

```text
$ dig +short api.YOUR_DOMAIN.com
104.21.58.123
172.67.204.33
# (Cloudflare IP addresses)
```

```text
$ dig +short origin-api.YOUR_DOMAIN.com
13.48.57.16
# (Your EC2 public IP)
```

Note: DNS propagation may take 1-5 minutes. Re-run checks after a short wait if values look stale.
