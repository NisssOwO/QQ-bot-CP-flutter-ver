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
Start-Sleep -Seconds 8
$activity = Invoke-Adb @('shell', 'dumpsys', 'activity', 'activities')
if ($activity -notmatch '(topResumedActivity|ResumedActivity):?=.*com\.shinycolors\.officialbot/.MainActivity' -and $activity -notmatch 'Resumed: ActivityRecord.*com\.shinycolors\.officialbot/.MainActivity') { throw 'MainActivity 没有进入前台' }
$uiPath = '/sdcard/qqbotcp-smoke-ui.xml'
Invoke-Adb @('shell', 'uiautomator', 'dump', $uiPath) | Out-Null
$ui = Invoke-Adb @('shell', 'cat', $uiPath)
foreach ($text in @('QQ-bot-CP', '设备公网 IP', 'AI 接口', '角色', '首次启动说明', '启动 Runtime')) { if ($ui -notmatch [regex]::Escape($text)) { throw "UI 缺少关键文案：$text" } }
Invoke-Adb @('shell', 'input', 'tap', '2304', '1488') | Out-Null
Start-Sleep -Seconds 1
Invoke-Adb @('shell', 'input', 'swipe', '1800', '1300', '1800', '350', '500') | Out-Null
Start-Sleep -Seconds 1
Invoke-Adb @('shell', 'uiautomator', 'dump', $uiPath) | Out-Null
$settingsUi = Invoke-Adb @('shell', 'cat', $uiPath)
if ($settingsUi -notmatch '更新清单 URL') {
  Invoke-Adb @('shell', 'input', 'swipe', '1800', '1300', '1800', '300', '500') | Out-Null
  Start-Sleep -Seconds 1
  Invoke-Adb @('shell', 'uiautomator', 'dump', $uiPath) | Out-Null
  $settingsUi = Invoke-Adb @('shell', 'cat', $uiPath)
}
foreach ($text in @('设置', '更新清单 URL', '配置备份')) { if ($settingsUi -notmatch [regex]::Escape($text)) { throw "设置页缺少关键文案：$text" } }
Invoke-Adb @('shell', 'input', 'tap', '1792', '1488') | Out-Null
Start-Sleep -Seconds 1
Invoke-Adb @('shell', 'uiautomator', 'dump', $uiPath) | Out-Null
$rolesUi = Invoke-Adb @('shell', 'cat', $uiPath)
foreach ($text in @('角色', '角色管理', '新建角色', '默认角色')) { if ($rolesUi -notmatch [regex]::Escape($text)) { throw "角色页缺少关键文案：$text" } }
Invoke-Adb @('shell', 'input', 'tap', '768', '1488') | Out-Null
Start-Sleep -Seconds 1
Invoke-Adb @('shell', 'uiautomator', 'dump', $uiPath) | Out-Null
$aiTop = Invoke-Adb @('shell', 'cat', $uiPath)
foreach ($text in @('拉取模型', '思考程度')) { if ($aiTop -notmatch [regex]::Escape($text)) { throw "AI 配置页缺少关键文案：$text" } }
Invoke-Adb @('shell', 'input', 'swipe', '1800', '1300', '1800', '400', '500') | Out-Null
Start-Sleep -Seconds 1
Invoke-Adb @('shell', 'uiautomator', 'dump', $uiPath) | Out-Null
$aiUi = Invoke-Adb @('shell', 'cat', $uiPath)
if ($aiUi -notmatch 'AI API Key') { throw 'AI 配置页缺少关键文案：AI API Key' }
$receivers = Invoke-Adb @('shell', 'dumpsys', 'package', 'com.shinycolors.officialbot')
if ($receivers -notmatch 'RuntimeWidgetProvider') { throw 'RuntimeWidgetProvider 未注册' }
Write-Output 'PASS Android 16 arm64 smoke test'
Write-Output "sdk=$($sdk.Trim()) abi=$($abi.Trim())"
