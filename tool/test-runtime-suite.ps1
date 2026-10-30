$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$runtime = Join-Path $root 'android\app\src\main\assets\runtime\runtime'
$tests = Get-ChildItem -LiteralPath $runtime -Filter 'test-*.mjs' | Sort-Object Name
foreach ($test in $tests) {
  & node $test.FullName
  if ($LASTEXITCODE -ne 0) { throw "Runtime 回归测试失败：$($test.Name)" }
}
Write-Output "PASS runtime suite ($($tests.Count) tests)"
