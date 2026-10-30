$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$runtime = Join-Path $root 'android\app\src\main\assets\runtime\runtime'
foreach ($test in @('test-official-event-normalizer.mjs', 'test-session-role-store.mjs', 'test-official-orchestrator.mjs')) {
  & node (Join-Path $runtime $test)
  if ($LASTEXITCODE -ne 0) { throw "官方会话测试失败：$test" }
}
Write-Output 'PASS official private/group session isolation smoke test'
