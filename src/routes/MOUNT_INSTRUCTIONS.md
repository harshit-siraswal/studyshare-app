# How to mount attendance_email_routes.ts in the backend

These two route handlers need to be registered in the Express app that
runs on the EC2 instance (`harshit-siraswal/studyshare-backend`).

## 1. Add imports (wherever your attendance/KIET routes are already registered)

```ts
import {
  connectCollegeEmailHandler,
  disconnectCollegeEmailHandler,
} from './routes/attendance_email_routes';
```

## 2. Mount the routes (add these two lines near the existing KIET/attendance routes)

```ts
// College email OAuth — Gmail token exchange & storage
app.post('/api/attendance/email/connect',    connectCollegeEmailHandler);
app.delete('/api/attendance/email/disconnect', disconnectCollegeEmailHandler);
```

The handlers read the user ID from `req.user.id` (populated by your existing
auth middleware) or fall back to extracting it from the raw `Authorization: Bearer`
JWT, so no changes to your middleware are needed.

## 3. Environment variables to add on EC2 / GitHub Actions secrets

| Variable | Description |
|---|---|
| `GOOGLE_COLLEGE_OAUTH_CLIENT_ID` | Web-type OAuth 2.0 Client ID from GCP Console |
| `GOOGLE_COLLEGE_OAUTH_CLIENT_SECRET` | Secret for the above client |
| `GOOGLE_COLLEGE_OAUTH_REDIRECT_URI` | Leave as `postmessage` for mobile server-auth-code flow |
| `CYBERVIDYA_VAULT_SECRET` | Master AES key (already used by CyberVidyaVaultService) |

`SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are already set — no change needed.

## 4. Run the SQL migration

Run `migrations/062_college_email_tokens_ensure.sql` in the Supabase SQL Editor
(or via `psql`). Migration 061 already created the table; 062 adds the
auto-update trigger, service-role policy, and indexes.
