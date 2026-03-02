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

# Patch flutter_app_badger for AGP 8+ (namespace + compileSdk)
# This plugin is unmaintained at v1.5.0 and needs these fixes for modern builds.
$badgerDir = "$env:LOCALAPPDATA\Pub\Cache\hosted\pub.dev\flutter_app_badger-1.5.0\android"
if (Test-Path "$badgerDir\build.gradle") {
    Write-Host "Patching flutter_app_badger for AGP 8+..." -ForegroundColor Yellow
    $gradle = Get-Content "$badgerDir\build.gradle" -Raw
    # Add namespace if missing
    if ($gradle -notmatch "namespace") {
        $gradle = $gradle -replace "android \{", "android {`n    namespace 'fr.g123k.flutterappbadge'"
    }
    # Bump compileSdkVersion to 34
    $gradle = $gradle -replace "compileSdkVersion \d+", "compileSdkVersion 34"
    Set-Content "$badgerDir\build.gradle" $gradle -NoNewline
    # Remove package attribute from AndroidManifest.xml
    $manifest = "$badgerDir\src\main\AndroidManifest.xml"
    if (Test-Path $manifest) {
        $xml = Get-Content $manifest -Raw
        $xml = $xml -replace '\s*package="[^"]*"', ''
        Set-Content $manifest $xml -NoNewline
    }
    Write-Host "flutter_app_badger patched successfully." -ForegroundColor Green
}

$buildArgs = @("build", "apk", "--release", "--verbose")

$envFile = Join-Path $PSScriptRoot ".env"
if (Test-Path $envFile) {
    Write-Host "Using --dart-define-from-file=.env" -ForegroundColor Cyan
    $buildArgs += "--dart-define-from-file=.env"
}
else {
    Write-Host ".env not found. Falling back to process environment variables only." -ForegroundColor Yellow
}

# Explicit environment variables override values coming from .env.
$defineKeys = @(
    "API_URL",
    "API_FALLBACK_URLS",
    "SUPABASE_URL",
    "SUPABASE_ANON_KEY",
    "GIPHY_API_KEY",
    "REMOVE_BG_API_KEY",
    "RAZORPAY_KEY_ID",
    "GOOGLE_SERVER_CLIENT_ID"
)

foreach ($key in $defineKeys) {
    $value = [Environment]::GetEnvironmentVariable($key)
    if ($null -ne $value -and $value -ne "") {
        Write-Host "Using $key from environment override" -ForegroundColor Cyan
        $buildArgs += "--dart-define=$key=$value"
    }
}

if (-not $env:GIPHY_API_KEY -and -not (Test-Path $envFile)) {
    Write-Host "GIPHY_API_KEY not supplied. GIF features will be disabled." -ForegroundColor Yellow
}

if (-not $env:REMOVE_BG_API_KEY -and -not (Test-Path $envFile)) {
    Write-Host "REMOVE_BG_API_KEY not supplied. Background removal will fail at runtime." -ForegroundColor Yellow
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
