# Runtime Secrets Setup (Flutter)

This app reads runtime secrets using `String.fromEnvironment(...)`.
Do not hardcode keys in Dart files.

## Required behavior

- Keep secret defaults empty in source code.
- Provide values at build/run time via `--dart-define` or `--dart-define-from-file`.
- Keep local `.env` gitignored.

## Local setup

1. Create a local secrets file:
   - Copy `.env.example` to `.env`
2. Add your own values:
   - `GIPHY_API_KEY`
   - `REMOVE_BG_API_KEY`
   - other environment values as needed

## Run examples

```bash
flutter run --dart-define-from-file=.env
```

```bash
flutter build apk --release --dart-define-from-file=.env
```

## CI/CD example

Inject secrets from your CI secret manager:

```bash
flutter build apk --release \
  --dart-define=GIPHY_API_KEY=$GIPHY_API_KEY \
  --dart-define=REMOVE_BG_API_KEY=$REMOVE_BG_API_KEY
```

## EC2 build setup

If you build the Flutter APK on EC2, keys must be present on that EC2 build machine
at build time (not only on your laptop).

Option A: Keep a local `.env` on EC2 and build from file:

```bash
cd flutter_application_1
cp .env.example .env
# fill values
flutter build apk --release --dart-define-from-file=.env
```

Option B: Use EC2 environment variables (recommended for automation):

```bash
export GIPHY_API_KEY="..."
export REMOVE_BG_API_KEY="..."
flutter build apk --release \
  --dart-define=GIPHY_API_KEY=$GIPHY_API_KEY \
  --dart-define=REMOVE_BG_API_KEY=$REMOVE_BG_API_KEY
```

Runtime note:
- Mobile app keys are compiled into the app build.
- EC2 runtime does not affect already-built APK keys.
- If you rotate keys, rebuild and redeploy the app.

## Notes

- Never commit `.env`.
- If `REMOVE_BG_API_KEY` is empty, background-removal features should fail fast with a clear error.
- If `GIPHY_API_KEY` is empty, GIF features should stay disabled gracefully.
