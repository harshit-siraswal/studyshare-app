# Set Java Home
$env:JAVA_HOME = "C:\Program Files\Eclipse Adoptium\jdk-17.0.17.10-hotspot"

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
# Build APK
Write-Host "Building APK..." -ForegroundColor Green
flutter build apk --release --verbose
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
