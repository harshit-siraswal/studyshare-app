# 06 - Verification Checklist (Run Exactly)

Run these from local PowerShell.

## A. Health checks

```powershell
curl.exe -i "https://api.studyshare.in/health"
curl.exe -i "https://admin-studyspace.vercel.app/api/admin/push-notification" -H "Authorization: Bearer test" # intentionally invalid token
```

Expected:
- `/health` => `200`
- admin endpoint => `401/403` (not `404/500`)

## B. CORS preflight checks

```powershell
curl.exe -i -X OPTIONS "https://api.studyshare.in/api/auth/verify" -H "Origin: https://studyshare.in" -H "Access-Control-Request-Method: POST" -H "Access-Control-Request-Headers: content-type,authorization"
curl.exe -i -X OPTIONS "https://api.studyshare.in/api/auth/verify" -H "Origin: https://admin-studyspace.vercel.app" -H "Access-Control-Request-Method: POST" -H "Access-Control-Request-Headers: content-type,authorization"
```

Expected:
- No 500
- Preflight should be handled without backend crash
- `OPTIONS` should return `200`/`204`
- `Access-Control-Allow-Origin` present (exact allowed origin or `*`)
- `Access-Control-Allow-Methods` includes expected methods (`GET, POST, OPTIONS`)
- `Access-Control-Allow-Headers` includes expected custom headers
- `Access-Control-Allow-Credentials` present when credentials are required

## C. Auth-required endpoint behavior

```powershell
curl.exe -i -X POST "https://api.studyshare.in/api/notices/demo/comments/demo/like" -H "Content-Type: application/json" -d "{}"
```

Expected:
- `401 Unauthorized` with auth error JSON

## D. Browser smoke test

1. Web app (`https://studyshare.in`)
- Login
- Open notifications
- Join chat

2. Admin app (`https://admin-studyspace.vercel.app`)
- Login
- Open resources tab
- Change one resource status
- Open reports tab
- Open push notifications tab

## E. If anything fails

1. Check EC2 backend logs:
```bash
docker compose logs -f api
```
or
```bash
pm2 logs
```

2. Check Worker logs:
- Cloudflare Dashboard -> Workers & Pages -> `studyspace-edge` -> Logs

3. Check Vercel logs:
- Vercel project -> Deployments -> latest -> Functions logs
