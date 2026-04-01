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

$buildArgs = @("build", "apk", "--release")

$targetPlatforms = [Environment]::GetEnvironmentVariable("APP_TARGET_PLATFORMS")
if (-not [string]::IsNullOrWhiteSpace($targetPlatforms)) {
    Write-Host "Using target platforms: $targetPlatforms" -ForegroundColor Cyan
    $buildArgs += "--target-platform=$targetPlatforms"
}

$overrideBuildName = [Environment]::GetEnvironmentVariable("APP_BUILD_NAME")
if (-not [string]::IsNullOrWhiteSpace($overrideBuildName)) {
    $buildName = $overrideBuildName.Trim()
    $allowedBuildNamePattern = '^[0-9]+(?:\.[0-9]+)*(?:-[0-9A-Za-z]+(?:\.[0-9A-Za-z]+)*)?$'
    if ($buildName -notmatch $allowedBuildNamePattern) {
        Write-Host "Error: APP_BUILD_NAME must use semantic-version style characters only (digits, dots, and optional prerelease suffix like -rc.1)." -ForegroundColor Red
        exit 1
    }
    Write-Host "Using build name override: $buildName" -ForegroundColor Cyan
    $buildArgs += "--build-name=$buildName"
}

$overrideBuildNumber = [Environment]::GetEnvironmentVariable("APP_BUILD_NUMBER")
if (-not [string]::IsNullOrWhiteSpace($overrideBuildNumber)) {
    $buildNumber = $overrideBuildNumber.Trim()
    if ($buildNumber -notmatch '^[1-9][0-9]*$') {
        Write-Host "Error: APP_BUILD_NUMBER must be a positive integer without leading zeros and within allowed range." -ForegroundColor Red
        exit 1
    }
    try {
        $buildNumberValue = [int64]$buildNumber
    }
    catch {
        Write-Host "Error: APP_BUILD_NUMBER must be a positive integer without leading zeros and within allowed range." -ForegroundColor Red
        exit 1
    }
    if ($buildNumberValue -gt 2147483647) {
        Write-Host "Error: APP_BUILD_NUMBER must be a positive integer without leading zeros and within allowed range." -ForegroundColor Red
        exit 1
    }
    Write-Host "Using build number override: $buildNumberValue" -ForegroundColor Cyan
    $buildArgs += "--build-number=$buildNumberValue"
}

$envFile = Join-Path $PSScriptRoot ".env"
$envFileContent = $null
if (Test-Path $envFile) {
    try {
        $envFileContent = Get-Content -Path $envFile -Raw -ErrorAction Stop
    }
    catch {
        Write-Host "Error: Failed to read $envFile. $_" -ForegroundColor Red
        exit 1
    }

    if ([string]::IsNullOrWhiteSpace($envFileContent)) {
        Write-Host "Error: $envFile exists but is empty/unreadable. Fix the file or remove it to use environment variables only." -ForegroundColor Red
        exit 1
    }

    Write-Host "Using --dart-define-from-file=$envFile" -ForegroundColor Cyan
    $buildArgs += "--dart-define-from-file=$envFile"
}
else {
    Write-Host ".env not found. Falling back to process environment variables only." -ForegroundColor Yellow
}

function Test-EnvKeyPresent {
    param(
        [string]$Content,
        [string]$Key
    )
    if ([string]::IsNullOrEmpty($Content)) { return $false }
    $escaped = [regex]::Escape($Key)
    return [regex]::IsMatch($Content, "(?m)^\s*$escaped\s*=")
}

# Explicit environment variables override values coming from .env.
$firebaseKeys = @(
    "FIREBASE_API_KEY",
    "FIREBASE_APP_ID",
    "FIREBASE_MESSAGING_SENDER_ID",
    "FIREBASE_PROJECT_ID",
    "FIREBASE_AUTH_DOMAIN",
    "FIREBASE_STORAGE_BUCKET"
)

$defineKeys = @(
    "API_URL",
    "API_FALLBACK_URLS",
    "SUPABASE_URL",
    "SUPABASE_ANON_KEY",
    "GIPHY_API_KEY",
    "REMOVE_BG_API_KEY",
    "RAZORPAY_KEY_ID",
    "GOOGLE_SERVER_CLIENT_ID",
    "RECAPTCHA_SITE_KEY",
    "TENOR_API_KEY",
    "MAX_SESSION_AGE_HOURS"
) + $firebaseKeys

foreach ($key in $defineKeys) {
    $value = [Environment]::GetEnvironmentVariable($key)
    if ($null -ne $value -and $value -ne "") {
        if ($value.Contains("`r") -or $value.Contains("`n") -or $value.Contains([char]0)) {
            Write-Host "Skipping $key override: value contains unsupported control characters." -ForegroundColor Yellow
            continue
        }
        $safeValue = $value.Replace('\', '\\').Replace('"', '\"')
        Write-Host "Using $key from environment override" -ForegroundColor Cyan
        $buildArgs += "--dart-define=$key=$safeValue"
    }
}

if (-not $env:GIPHY_API_KEY -and -not (Test-EnvKeyPresent -Content $envFileContent -Key "GIPHY_API_KEY")) {
    Write-Host "GIPHY_API_KEY not supplied. GIF features will be disabled." -ForegroundColor Yellow
}

if (-not $env:REMOVE_BG_API_KEY -and -not (Test-EnvKeyPresent -Content $envFileContent -Key "REMOVE_BG_API_KEY")) {
    Write-Host "REMOVE_BG_API_KEY not supplied. Background removal will fail at runtime." -ForegroundColor Yellow
}

if (-not $env:RECAPTCHA_SITE_KEY -and -not (Test-EnvKeyPresent -Content $envFileContent -Key "RECAPTCHA_SITE_KEY")) {
    Write-Host "RECAPTCHA_SITE_KEY not supplied. Sensitive write protection will be reduced." -ForegroundColor Yellow
}

if (-not $env:TENOR_API_KEY -and -not (Test-EnvKeyPresent -Content $envFileContent -Key "TENOR_API_KEY")) {
    Write-Host "TENOR_API_KEY not supplied. Tenor features will be disabled." -ForegroundColor Yellow
}

foreach ($firebaseKey in $firebaseKeys) {
    if (-not [Environment]::GetEnvironmentVariable($firebaseKey) -and -not (Test-EnvKeyPresent -Content $envFileContent -Key $firebaseKey)) {
        Write-Host "$firebaseKey not supplied. Firebase features may fail at runtime." -ForegroundColor Yellow
    }
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
