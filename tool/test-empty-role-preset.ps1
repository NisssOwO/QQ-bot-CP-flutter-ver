$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$test = Join-Path $root 'android\app\src\main\assets\runtime\runtime\test-role-command-empty.mjs'
if (-not (Test-Path -LiteralPath $test)) { throw "运行包角色测试不存在：$test" }
& node $test
if ($LASTEXITCODE -ne 0) { throw '空角色 /presets 测试失败' }
Write-Output 'PASS empty role preset smoke test'
