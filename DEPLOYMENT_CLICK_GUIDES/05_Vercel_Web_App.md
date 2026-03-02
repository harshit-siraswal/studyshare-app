# 05 - Vercel Web App Setup

Project path: `<your-local-project-directory>`

## A. Open web project environment variables

1. Go to `https://vercel.com/dashboard`
2. Click project: your Studyspace web app
3. Click **Settings**
4. Click **Environment Variables**

## B. Set API URL

1. Add/update:
- `VITE_API_URL` = `https://api.studyshare.in` (apply to **Production** and **Preview**)

2. Click **Save**

## C. Redeploy web app

1. Click **Deployments**
2. Open latest deployment
3. Click menu `...`
4. Click **Redeploy**
5. Click **Redeploy**

## D. Verify web app API calls

1. Open your web app (`https://studyshare.in`)
2. Login with a test user
3. Confirm these work:
- Profile load
- Notifications load
- Chat room list
- Start a test upload from the upload dialog
- Verify a signed upload URL is returned (a URL containing upload authentication tokens)
- Confirm the upload completes successfully
