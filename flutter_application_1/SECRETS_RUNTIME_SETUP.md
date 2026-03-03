# Runtime Secrets Setup (Flutter)

This app reads runtime secrets using `String.fromEnvironment(...)`.
Do not hardcode keys in Dart files.

## Security warning

Values loaded through `String.fromEnvironment(...)` are compile-time constants and are embedded in APK/IPA binaries.
They can be extracted by reverse engineering tools (for example `apktool`).
This is a normal mobile-app limitation, so avoid embedding high-privilege secrets.
Prefer backend APIs (with proper auth) for sensitive operations, and keep using `--dart-define` / `--dart-define-from-file` with empty defaults in source.

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

### GitHub Actions

```yaml
- name: Build APK
  run: |
    flutter build apk --release \
      --dart-define=GIPHY_API_KEY=${{ secrets.GIPHY_API_KEY }} \
      --dart-define=REMOVE_BG_API_KEY=${{ secrets.REMOVE_BG_API_KEY }}
```

### GitLab CI

```yaml
build_apk:
  script:
    - >
      flutter build apk --release
      --dart-define=GIPHY_API_KEY=$GIPHY_API_KEY
      --dart-define=REMOVE_BG_API_KEY=$REMOVE_BG_API_KEY
```

## EC2 build setup

If you build the Flutter APK on EC2, keys must be present on that EC2 build machine
at build time (not only on your laptop).

Option A: Fetch secrets during build (recommended):

```bash
cd flutter_application_1
# Example: AWS Secrets Manager / SSM fetch to environment variables
# Replace `...` with your real secret identifiers/flags (for example: secret-id, parameter name, region, and `--with-decryption`).
# export GIPHY_API_KEY="$(aws secretsmanager get-secret-value ...)" # target env var: GIPHY_API_KEY
# export REMOVE_BG_API_KEY="$(aws ssm get-parameter ... --with-decryption ...)" # target env var: REMOVE_BG_API_KEY
flutter build apk --release \
  --dart-define=GIPHY_API_KEY=$GIPHY_API_KEY \
  --dart-define=REMOVE_BG_API_KEY=$REMOVE_BG_API_KEY
```

Option B: Use EC2 environment variables directly (recommended for automation):

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
