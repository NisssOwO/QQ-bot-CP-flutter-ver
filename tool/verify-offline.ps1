$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$flutter = if ($env:FLUTTER_ROOT) { Join-Path $env:FLUTTER_ROOT 'bin\flutter.bat' } else { 'F:\flutter\flutter_windows_3.47.9-stable\flutter\bin\flutter.bat' }
$dart = if ($env:FLUTTER_ROOT) { Join-Path $env:FLUTTER_ROOT 'bin\dart.bat' } else { 'F:\flutter\flutter_windows_3.47.9-stable\flutter\bin\dart.bat' }
Push-Location $root
try {
  & $flutter test
  if ($LASTEXITCODE -ne 0) { throw 'Flutter 测试失败' }
  & $dart analyze --format machine
  if ($LASTEXITCODE -ne 0) { throw 'Dart 静态分析失败' }
  & .\tool\test-runtime-suite.ps1
  & .\tool\test-empty-role-preset.ps1
  & .\tool\test-official-session-isolation.ps1
  $apk = Join-Path $root 'build\app\outputs\flutter-apk\app-debug.apk'
  if (Test-Path -LiteralPath $apk) {
    $env:Path = "F:\Android\Android Studio\jbr\bin;$env:Path"
    & .\tool\audit-release.ps1 -Apk $apk
  } else {
    Write-Warning '未找到 Debug APK，跳过 APK 审计；先运行 tool/build-arm64-debug.ps1。'
  }
  Write-Output 'PASS offline verification gate'
} finally { Pop-Location }
