# 06 - Verification Checklist (Run Exactly)

Run these from local PowerShell.

## A. Health checks

```powershell
curl.exe -i "https://api.mystudyspace.in/health"
curl.exe -i "https://admin-studyspace.vercel.app/api/admin/push-notification" -H "Authorization: Bearer test" # intentionally invalid token
```

Expected:
- `/health` => `200`
- admin endpoint => `401/403` (not `404/500`)

## B. CORS preflight checks

```powershell
curl.exe -i -X OPTIONS "https://api.mystudyspace.in/api/auth/verify" -H "Origin: https://mystudyspace.in" -H "Access-Control-Request-Method: POST" -H "Access-Control-Request-Headers: content-type,authorization"
curl.exe -i -X OPTIONS "https://api.mystudyspace.in/api/auth/verify" -H "Origin: https://www.mystudyspace.in" -H "Access-Control-Request-Method: POST" -H "Access-Control-Request-Headers: content-type,authorization"
curl.exe -i -X OPTIONS "https://api.mystudyspace.in/api/auth/verify" -H "Origin: https://admin-studyspace.vercel.app" -H "Access-Control-Request-Method: POST" -H "Access-Control-Request-Headers: content-type,authorization"
curl.exe -i -X OPTIONS "https://api.mystudyspace.in/api/auth/verify" -H "Origin: https://admin.mystudyspace.in" -H "Access-Control-Request-Method: POST" -H "Access-Control-Request-Headers: content-type,authorization"
```

Expected:
- No 500
- Preflight should be handled without backend crash
- `OPTIONS` should return `200`/`204`
- `Access-Control-Allow-Origin` exactly matches the request origin and is one of:
  - `https://mystudyspace.in`
  - `https://www.mystudyspace.in`
  - `https://admin-studyspace.vercel.app`
  - `https://admin.mystudyspace.in`
- `Access-Control-Allow-Methods` includes: `GET, POST, PUT, PATCH, DELETE, OPTIONS`
- `Access-Control-Allow-Headers` includes: `Authorization, Content-Type`
- `Access-Control-Allow-Credentials` should be omitted or `false` for this bearer-token deployment (no cookie auth expected)

## C. Auth-required endpoint behavior

```powershell
curl.exe -i -X POST "https://api.mystudyspace.in/api/notices/demo/comments/demo/like" -H "Content-Type: application/json" -d "{}"
```

Expected:
- `401 Unauthorized` with auth error JSON

## D. Browser smoke test

1. Web app (`https://mystudyspace.in`)
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

1. SSH into EC2 and run backend log checks there (not in local PowerShell):
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

