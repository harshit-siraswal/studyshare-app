# Set Java Home
$JavaHome = $env:JAVA_HOME
if (-not $JavaHome) {
    $JavaHome = "C:\Program Files\Eclipse Adoptium\jdk-17.0.17.10-hotspot"
}

if (-not (Test-Path $JavaHome)) {
    Write-Host "Error: JAVA_HOME path does not exist: $JavaHome" -ForegroundColor Red
    exit 1
}

$env:JAVA_HOME = $JavaHome

Write-Host "Java Home set to: $env:JAVA_HOME" -ForegroundColor Cyan
# Clean
Write-Host "Cleaning project..." -ForegroundColor Green
flutter clean
if ($LASTEXITCODE -ne 0) {
    Write-Host "flutter clean failed!" -ForegroundColor Red
    exit $LASTEXITCODE
}
if (Test-Path "android\.gradle") { Remove-Item -Recurse -Force android\.gradle -ErrorAction SilentlyContinue }
if (Test-Path "android\app\build") { Remove-Item -Recurse -Force android\app\build -ErrorAction SilentlyContinue }

# Get dependencies
Write-Host "Getting dependencies..." -ForegroundColor Green
flutter pub get
if ($LASTEXITCODE -ne 0) {
    Write-Host "flutter pub get failed!" -ForegroundColor Red
    exit $LASTEXITCODE
}

$buildArgs = @("build", "apk", "--release", "--verbose")

if ($env:API_URL) {
    Write-Host "Using API_URL from environment (set)" -ForegroundColor Cyan
    $buildArgs += "--dart-define=API_URL=$($env:API_URL)"
}

if ($env:API_FALLBACK_URLS) {
    Write-Host "Using API_FALLBACK_URLS from environment" -ForegroundColor Cyan
    $buildArgs += "--dart-define=API_FALLBACK_URLS=$($env:API_FALLBACK_URLS)"
}

# Build APK
Write-Host "Building APK..." -ForegroundColor Green
& flutter @buildArgs
if ($LASTEXITCODE -ne 0) {
    Write-Host "flutter build apk failed!" -ForegroundColor Red
    exit $LASTEXITCODE
}

# Show output location
if ($LASTEXITCODE -eq 0) {
    Write-Host "`nBuild successful! APK location:" -ForegroundColor Green
    Write-Host "build\app\outputs\flutter-apk\" -ForegroundColor Yellow
}
else {
    Write-Host "`nBuild failed!" -ForegroundColor Red
}
