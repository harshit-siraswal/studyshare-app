# 03 - Cloudflare Worker Setup

This matches the worker code now in your repo (`ORIGIN_API_BASE_URL` is required).
Prerequisites: install Wrangler CLI and authenticate first (`wrangler login`).

## A. Deploy worker code

1. Open a terminal in your cloned project directory.
2. Run:

```powershell
npx wrangler deploy
```

## B. Set worker environment variable

1. Go to `https://dash.cloudflare.com`
2. Click your account
3. Left menu: **Workers & Pages**
4. Click worker: `studyspace-edge` (example; use your worker name)
5. Click **Settings**
6. Click **Variables**
7. Under **Environment Variables**, click **Add variable**
8. Name: `ORIGIN_API_BASE_URL`
9. Value: `https://origin-api.mystudyspace.in` (example; replace with your origin API base URL)
10. Click **Save and deploy**

## C. Add worker route

1. In the same worker, open **Triggers**
2. Under **Routes**, click **Add route**
3. Route: `api.mystudyspace.in/*` (example; replace with your route)
4. Zone: `mystudyspace.in` (example; replace with your zone)
5. Click **Add route**

## D. Verify worker is forwarding correctly

Replace `your-domain.example` below with your own public API domain.

Run locally:

```powershell
curl -i "https://your-domain.example/health" # Replace /health with any valid endpoint from your API
```

Windows alternative:

```powershell
curl.exe -i "https://your-domain.example/health" # Replace /health with any valid endpoint from your API
```

Expect: `HTTP/1.1 200 OK`

