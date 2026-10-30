param(
  [string]$Apk = ""
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($Apk)) {
  $Apk = Join-Path $projectRoot 'build\app\outputs\flutter-apk\app-release.apk'
}
if (-not (Test-Path -LiteralPath $Apk)) { throw "APK 不存在：$Apk" }

$apkItem = Get-Item -LiteralPath $Apk
$hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $Apk).Hash.ToLowerInvariant()
$entries = & jar tf $Apk
$forbiddenEntries = $entries | Where-Object {
  $_ -match '(?i)^assets/runtime/\.dsh-home/(sessions|storage|credentials)(/|$)' -or
  $_ -match '(?i)^assets/runtime/\.dsh-home/profiles/[^/]+/(user-presets|presets)(/|$)' -or
  $_ -match '(?i)^assets/runtime/(user-presets|presets)(/|$)' -or
  $_ -match '(?i)^assets/runtime/.*/preset\.[^/]+\.(md|json)$' -or
  $_ -match '(?i)(^|/)\.env$'
}
if ($forbiddenEntries) { throw "APK 包含疑似用户数据文件：$($forbiddenEntries -join ', ')" }

$textExtensions = @('.js', '.mjs', '.cjs', '.json', '.md', '.txt', '.xml', '.yml', '.yaml', '.properties', '.kt', '.dart', '.gradle', '.kts')
$suspicious = @()
$archive = [System.IO.Compression.ZipFile]::OpenRead((Resolve-Path -LiteralPath $Apk))
try {
  foreach ($entry in $archive.Entries) {
    if ($entry.FullName -notmatch '(?i)^assets/runtime/(runtime/|plugins/|\.dsh-home/profiles/qqbot/)') { continue }
    $extension = [IO.Path]::GetExtension($entry.FullName).ToLowerInvariant()
    if ($entry.Length -eq 0 -or $textExtensions -notcontains $extension) { continue }
    try {
      $reader = [IO.StreamReader]::new($entry.Open())
      $text = $reader.ReadToEnd()
      $reader.Dispose()
      if ($text -match '(?i)(QQBOT_APPID\s*[=:]\s*["'']?\d{5,}|QQBOT_SECRET\s*[=:]\s*["''][^"'']{8,}["'']|LLM_API_KEY\s*[=:]\s*["''][^"'']{12,}["''])') { $suspicious += $entry.FullName }
    } catch { }
  }
} finally { $archive.Dispose() }
if ($suspicious) { throw "APK 包含疑似凭据内容：$($suspicious -join ', ')" }

Write-Output "PASS release audit"
Write-Output "path=$Apk"
Write-Output "sizeBytes=$($apkItem.Length)"
Write-Output "sha256=$hash"
