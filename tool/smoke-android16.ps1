param(
  [string]$Serial = "",
  [string]$Apk = ""
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$adb = if ($env:ANDROID_HOME) { Join-Path $env:ANDROID_HOME 'platform-tools\adb.exe' } else { 'F:\Android\Sdk\platform-tools\adb.exe' }
if (-not (Test-Path $adb)) { throw "找不到 adb：$adb" }
if ([string]::IsNullOrWhiteSpace($Apk)) { $Apk = Join-Path $root 'build\app\outputs\flutter-apk\app-debug.apk' }
if (-not (Test-Path -LiteralPath $Apk)) { throw "APK 不存在：$Apk" }

function Invoke-Adb([string[]]$CommandArgs) {
  $all = @(); if ($Serial) { $all += '-s'; $all += $Serial }; $all += $CommandArgs
  $output = (& $adb @all 2>&1 | Out-String)
  $code = $LASTEXITCODE
  if ($code -ne 0) { throw $output }
  return $output.Trim()
}

$devices = Invoke-Adb @('devices')
if ($devices -notmatch "(?m)^\S+\s+device$") { throw '没有检测到处于 device 状态的 Android 设备' }
$sdk = Invoke-Adb @('shell', 'getprop', 'ro.build.version.sdk')
$abi = Invoke-Adb @('shell', 'getprop', 'ro.product.cpu.abi')
if ($sdk.Trim() -ne '36') { throw "该脚本要求 Android SDK 36，实际为 $sdk" }
if ($abi.Trim() -ne 'arm64-v8a') { throw "该脚本要求 arm64-v8a，实际为 $abi" }
Invoke-Adb @('install', '-r', '-d', $Apk) | Out-Null
Invoke-Adb @('shell', 'monkey', '-p', 'com.shinycolors.officialbot', '1') | Out-Null
Start-Sleep -Seconds 3
$activity = Invoke-Adb @('shell', 'dumpsys', 'activity', 'activities')
if ($activity -notmatch '(topResumedActivity|ResumedActivity):?=.*com\.shinycolors\.officialbot/.MainActivity' -and $activity -notmatch 'Resumed: ActivityRecord.*com\.shinycolors\.officialbot/.MainActivity') { throw 'MainActivity 没有进入前台' }
$uiPath = '/sdcard/qqbotcp-smoke-ui.xml'
Invoke-Adb @('shell', 'uiautomator', 'dump', $uiPath) | Out-Null
$ui = Invoke-Adb @('shell', 'cat', $uiPath)
foreach ($text in @('QQ-bot-CP', '设备公网 IP', 'AI 接口', '角色')) { if ($ui -notmatch [regex]::Escape($text)) { throw "UI 缺少关键文案：$text" } }
$receivers = Invoke-Adb @('shell', 'dumpsys', 'package', 'com.shinycolors.officialbot')
if ($receivers -notmatch 'RuntimeWidgetProvider') { throw 'RuntimeWidgetProvider 未注册' }
Write-Output 'PASS Android 16 arm64 smoke test'
Write-Output "sdk=$($sdk.Trim()) abi=$($abi.Trim())"
