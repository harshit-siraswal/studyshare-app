# 04 - Vercel Admin Dashboard Setup

Project path: `<local-project-path>`

## A. Open project environment variables

1. Go to `https://vercel.com/dashboard`
2. Click project: **admin-studyspace**
3. Click **Settings**
4. Click **Environment Variables**

## B. Set required variables

Add/update these:

1. `BACKEND_API_BASE_URL` = `https://api.studyshare.in`
2. `CORS_ALLOWED_ORIGINS` = `https://admin-studyspace.vercel.app,https://admin.studyshare.in`
3. `SUPABASE_URL` = `<your-supabase-url>`
4. `SUPABASE_SERVICE_ROLE_KEY` = `<your-service-role-key>`
5. `RECAPTCHA_PROJECT_ID` = `<your-gcp-project-id>`
6. `RECAPTCHA_SITE_KEY` = `<your-recaptcha-site-key>`
7. `RECAPTCHA_API_KEY` = `<your-google-api-key>`
8. `RECAPTCHA_ALLOWED_HOSTNAMES` = `admin-studyspace.vercel.app,admin.studyshare.in`
9. `RECAPTCHA_ALLOWED_ORIGINS` = `https://admin-studyspace.vercel.app,https://admin.studyshare.in`

For each variable:
- Click **Add New**
- Enter key/value
- Select environments: Production, Preview (as needed)
- Click **Save**

## C. Redeploy admin

1. Click **Deployments**
2. Open latest deployment
3. Click menu `...`
4. Click **Redeploy**
5. Enable **Use existing Build Cache** (optional)
6. Click **Redeploy**

## D. Verify admin API from browser

1. Open `https://admin-studyspace.vercel.app`
2. Login
3. Confirm: resource list loads, reports load, push config loads.
