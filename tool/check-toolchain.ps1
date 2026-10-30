$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$expected = Get-Content (Join-Path $PSScriptRoot 'toolchain.json') -Raw | ConvertFrom-Json

$flutter = & flutter --version 2>&1 | Out-String
if ($flutter -notmatch "Flutter $([regex]::Escape($expected.flutter))") { throw "Flutter 版本不匹配，期望 $($expected.flutter)" }
if ($flutter -notmatch "Dart $([regex]::Escape($expected.dart))") { throw "Dart 版本不匹配，期望 $($expected.dart)" }

$java = & java -version 2>&1 | Out-String
$javaPattern = 'version "' + [regex]::Escape("$($expected.javaMajor).")
if ($java -notmatch $javaPattern) { throw "JDK 主版本不匹配，期望 $($expected.javaMajor)" }

$wrapper = Get-Content (Join-Path $root 'android\gradle\wrapper\gradle-wrapper.properties') -Raw
if ($wrapper -notmatch "gradle-$([regex]::Escape($expected.gradle))-all\.zip") { throw "Gradle wrapper 版本不匹配" }
$settings = Get-Content (Join-Path $root 'android\settings.gradle.kts') -Raw
$agpPattern = 'com\.android\.application\"\) version \"' + [regex]::Escape($expected.androidGradlePlugin) + '\"'
$kotlinPattern = 'org\.jetbrains\.kotlin\.android\"\) version \"' + [regex]::Escape($expected.kotlin) + '\"'
if ($settings -notmatch $agpPattern) { throw "Android Gradle Plugin 版本不匹配" }
if ($settings -notmatch $kotlinPattern) { throw "Kotlin 插件版本不匹配" }

Write-Output "PASS toolchain check"
Write-Output "Flutter=$($expected.flutter) Dart=$($expected.dart) JDK=$($expected.javaMajor) Gradle=$($expected.gradle) AGP=$($expected.androidGradlePlugin) Kotlin=$($expected.kotlin)"
