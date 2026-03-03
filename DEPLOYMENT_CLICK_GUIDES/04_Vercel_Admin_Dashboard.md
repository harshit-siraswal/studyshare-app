# 04 - Vercel Admin Dashboard Setup

Project path: `<local-project-path>`

## A. Open project environment variables

1. Go to `https://vercel.com/dashboard`
2. Click project: **admin-studyspace**
3. Click **Settings**
4. Click **Environment Variables**

## B. Set required variables

Add/update these:

> **SECURITY WARNING:** `SUPABASE_SERVICE_ROLE_KEY` grants full database access and bypasses RLS. Never commit this key to version control, restrict access to essential personnel only, and rotate it regularly.
>
> **General secret handling:** Do not commit any API keys or secrets (`RECAPTCHA_API_KEY`, `RECAPTCHA_SITE_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, etc.) to version control. Store them only as environment variables, restrict access to least privilege, rotate them regularly, and scope/hostname-restrict where supported (for example `RECAPTCHA_ALLOWED_HOSTNAMES` / `RECAPTCHA_ALLOWED_ORIGINS`).

1. `BACKEND_API_BASE_URL` = `https://api.mystudyspace.in`
2. `CORS_ALLOWED_ORIGINS` = `https://admin-studyspace.vercel.app,https://admin.mystudyspace.in`
3. `SUPABASE_URL` = `<your-supabase-url>`
4. `SUPABASE_SERVICE_ROLE_KEY` = `<your-service-role-key>`
5. `RECAPTCHA_PROJECT_ID` = `<your-gcp-project-id>`
6. `RECAPTCHA_SITE_KEY` = `<your-recaptcha-site-key>`
7. `RECAPTCHA_API_KEY` = `<your-google-api-key>`
8. `RECAPTCHA_ALLOWED_HOSTNAMES` = `admin-studyspace.vercel.app,admin.mystudyspace.in`
9. `RECAPTCHA_ALLOWED_ORIGINS` = `https://admin-studyspace.vercel.app,https://admin.mystudyspace.in`

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
3. Verify environment/config wiring:
   - Confirm expected API base URL and feature-flag values in network requests and browser console logs.
4. Verify CRUD persistence:
   - Create, edit, and delete a resource from Admin Dashboard and confirm changes persist after refresh.
5. Verify CORS behavior:
   - Confirm no browser CORS errors and successful preflight (`OPTIONS`) responses on admin API calls.
6. Verify reCAPTCHA-protected flows:
   - Exercise reCAPTCHA endpoints and confirm token validation succeeds server-side.
7. Verify full auth flow:
   - Validate login, token refresh, and logout behavior while checking auth headers, expected responses, and error handling.

