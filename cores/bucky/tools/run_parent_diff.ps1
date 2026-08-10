param(
    [Parameter(Mandatory = $true)] [string] $Executable,
    [Parameter(Mandatory = $true)] [string] $RomDir,
    [Parameter(Mandatory = $true)] [string] $MameRomDir,
    [string] $WorkDir = (Join-Path $env:TEMP 'bucky-parent-diff'),
    [int] $MaxFrames = 2,
    [int] $MameSeconds = 1
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$work = [IO.Path]::GetFullPath($WorkDir)
New-Item -ItemType Directory -Force -Path $work | Out-Null
$reference = Join-Path $work 'mame-trace.jsonl'
$candidate = Join-Path $work 'rtl-trace.jsonl'

& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'cores\bucky\tools\run_mame_trace.ps1') `
    -RomDir $MameRomDir -WorkDir (Join-Path $work 'mame') -Seconds $MameSeconds -Output $reference
if ($LASTEXITCODE -ne 0) { throw 'MAME trace runner failed' }

& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'cores\bucky\tools\run_parent_sim.ps1') `
    -Executable $Executable -RomDir $RomDir -MaxFrames $MaxFrames -TraceFile $candidate
if ($LASTEXITCODE -ne 0) { throw 'Parent simulation runner failed' }

& python (Join-Path $root 'cores\bucky\tools\diff\compare_traces.py') `
    $reference $candidate --allow-candidate-tail --mask-inactive-data `
    --failure-report (Join-Path $work 'first-divergence.json')
if ($LASTEXITCODE -ne 0) { throw 'Parent/MAME bus differential failed' }
Write-Output "PASS: parent/MAME differential reference=$reference candidate=$candidate"
