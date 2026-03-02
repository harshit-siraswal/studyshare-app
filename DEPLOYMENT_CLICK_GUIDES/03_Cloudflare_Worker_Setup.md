# 03 - Cloudflare Worker Setup

This matches the worker code now in your repo (`ORIGIN_API_BASE_URL` is required).
Prerequisites: install Wrangler CLI and authenticate first (`wrangler login`).

## A. Deploy worker code

1. Open terminal in your cloned project directory (`<your-project-directory>`).
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
9. Value: `https://origin-api.studyshare.in` (example; replace with your origin API base URL)
10. Click **Save and deploy**

## C. Add worker route

1. In the same worker, open **Triggers**
2. Under **Routes**, click **Add route**
3. Route: `api.studyshare.in/*`
4. Zone: `studyshare.in`
5. Click **Add route**

## D. Verify worker is forwarding correctly

Replace `api.studyshare.in` below with your own public API domain.

Run locally:

```powershell
curl -i "https://your-domain.example/health"
```

Windows alternative:

```powershell
curl.exe -i "https://your-domain.example/health"
```

Expect: `HTTP/1.1 200 OK`
