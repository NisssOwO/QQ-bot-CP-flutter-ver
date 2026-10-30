param(
  [Parameter(Mandatory=$true)][string]$SourceRuntime,
  [string]$Destination = (Join-Path $PSScriptRoot '..\android\app\src\main\assets\runtime')
)
$ErrorActionPreference = 'Stop'
$source = (Resolve-Path $SourceRuntime).Path
$destination = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot $Destination))
if (-not (Test-Path (Join-Path $source 'runtime-entry.mjs'))) { throw "Invalid runtime bundle: $source" }
New-Item -ItemType Directory -Force $destination | Out-Null
robocopy $source $destination /E /XD "$source\presets" "$source\.dsh-home\sessions" "$source\.dsh-home\storages" /XF runtime-missing-dependencies.txt /R:1 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
Write-Host "Runtime bundle staged at $destination"
