# Set Java Home
$env:JAVA_HOME = "C:\Program Files\Android\Android Studio\jbr"

Write-Host "Java Home set to: $env:JAVA_HOME" -ForegroundColor Cyan

# Clean
Write-Host "Cleaning project..." -ForegroundColor Green
flutter clean
if (Test-Path "android\.gradle") { Remove-Item -Recurse -Force android\.gradle -ErrorAction SilentlyContinue }
if (Test-Path "android\app\build") { Remove-Item -Recurse -Force android\app\build -ErrorAction SilentlyContinue }

# Get dependencies
Write-Host "Getting dependencies..." -ForegroundColor Green
flutter pub get

# Build APK
Write-Host "Building APK..." -ForegroundColor Green
flutter build apk --release --verbose

# Show output location
if ($LASTEXITCODE -eq 0) {
    Write-Host "`nBuild successful! APK location:" -ForegroundColor Green
    Write-Host "build\app\outputs\flutter-apk\" -ForegroundColor Yellow
}
else {
    Write-Host "`nBuild failed!" -ForegroundColor Red
}
