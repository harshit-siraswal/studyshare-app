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

if ($env:API_URL) {
    Write-Host "Using API_URL from environment (set)" -ForegroundColor Cyan
    $buildArgs += "--dart-define=API_URL=$($env:API_URL)"
}

if ($env:API_FALLBACK_URLS) {
    Write-Host "Using API_FALLBACK_URLS from environment" -ForegroundColor Cyan
    $buildArgs += "--dart-define=API_FALLBACK_URLS=$($env:API_FALLBACK_URLS)"
}

# REMOVE_BG_API_KEY - environment var overrides hardcoded key
$removeBgKey = if ($env:REMOVE_BG_API_KEY) { $env:REMOVE_BG_API_KEY } else { "D53uXgDqrEyuxCXHXQWFZ7n4" }
$buildArgs += "--dart-define=REMOVE_BG_API_KEY=$removeBgKey"
Write-Host "Using REMOVE_BG_API_KEY" -ForegroundColor Cyan

# GIPHY_API_KEY - environment var overrides hardcoded key
if ($env:GIPHY_API_KEY) {
    $giphyKey = $env:GIPHY_API_KEY
    Write-Host "Using GIPHY_API_KEY from environment" -ForegroundColor Cyan
    $buildArgs += "--dart-define=GIPHY_API_KEY=$giphyKey"
}
else {
    $giphyKey = "E2CYfJbrw5NGA8aUUN2d8nDn4Q6PoH77"
    Write-Host "WARNING: GIPHY_API_KEY not set in environment. GIPHY features may be disabled or use fallback." -ForegroundColor Yellow
    $buildArgs += "--dart-define=GIPHY_API_KEY=$giphyKey"
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
