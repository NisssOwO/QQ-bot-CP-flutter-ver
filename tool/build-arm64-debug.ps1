$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$flutter = Get-Command flutter -ErrorAction Stop
Push-Location $root
try {
  & $flutter.Source build apk --debug --target-platform android-arm64
  if ($LASTEXITCODE -ne 0) { throw "arm64 Debug 构建失败" }
  Write-Output "PASS arm64 debug build"
  Write-Output (Join-Path $root 'build\app\outputs\flutter-apk\app-debug.apk')
} finally { Pop-Location }
