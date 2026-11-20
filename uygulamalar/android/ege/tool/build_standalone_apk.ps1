$ErrorActionPreference = "Stop"
# Builds a personal JARVIS APK with the CLI Proxy API keys embedded so the
# phone works on its own. The key file lives only in %TEMP% during the build.
$Root = Split-Path $PSScriptRoot -Parent
$Python = "C:\Users\mehmet\AppData\Local\Programs\Python\Python311\python.exe"
$Flutter = "C:\src\flutter\bin\flutter.bat"
$KeyFile = Join-Path $env:TEMP ("jarvis_keys_{0}.json" -f ([guid]::NewGuid().ToString("N")))
try {
    & $Python -I (Join-Path $PSScriptRoot "jarvis_keys.py") $KeyFile
    Push-Location $Root
    # realme 10 arm64: yalnız arm64 = daha küçük APK (JARVIS_ABIS ile değiştirilebilir)
    $abis = if ($env:JARVIS_ABIS) { $env:JARVIS_ABIS } else { "android-arm64" }
    & $Flutter build apk --release --no-pub "--target-platform=$abis" "--dart-define-from-file=$KeyFile"
    if ($LASTEXITCODE -ne 0) { throw "flutter build başarısız ($LASTEXITCODE)" }
    $version = (Select-String -Path (Join-Path $Root "pubspec.yaml") -Pattern '^version:\s*([0-9.]+)').Matches[0].Groups[1].Value
    $dist = Join-Path (Split-Path $Root -Parent) "dist"
    New-Item -ItemType Directory -Force $dist | Out-Null
    $out = Join-Path $dist "JARVIS-$version.apk"
    Copy-Item (Join-Path $Root "build\app\outputs\flutter-apk\app-release.apk") $out -Force
    Write-Host "APK hazır: $out" -ForegroundColor Green
} finally {
    Pop-Location -ErrorAction SilentlyContinue
    if (Test-Path $KeyFile) { Remove-Item $KeyFile -Force }
}
