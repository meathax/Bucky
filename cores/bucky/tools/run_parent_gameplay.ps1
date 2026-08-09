param(
    [Parameter(Mandatory = $true)] [string] $Executable,
    [Parameter(Mandatory = $true)] [string] $RomDir,
    [int] $MaxFrames = 600,
    [int] $CoinFrame = 470,
    [int] $Coin2Frame = -1,
    [int] $StartFrame = 510,
    [int] $InputPulse = 20,
    [string] $TraceFile = '',
    [string] $PpmFile = '',
    [int] $PpmFrame = 580,
    [string] $LogFile = '',
    [string] $MilestoneFile = ''
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$resolvedRomDir = (Resolve-Path -LiteralPath $RomDir).Path
if ([string]::IsNullOrWhiteSpace($TraceFile)) {
    $TraceFile = Join-Path $env:TEMP 'bucky-parent-gameplay.jsonl'
}

# This is the parent-only gameplay gate.  The frame positions mirror the MAME
# Lua input schedule: one credit pulse after attract, followed by a
# one-player-start pulse.  MAME 0.289 reaches the accepted-start path at frame
# 513 and the gameplay worker at frame 518 with these parent-set inputs.
& (Join-Path $root 'cores\bucky\tools\run_parent_sim.ps1') `
    -Executable $Executable -RomDir $resolvedRomDir -MaxFrames $MaxFrames -TraceMax 1 `
    -TraceFile $TraceFile -CoinFrame $CoinFrame -Coin2Frame $Coin2Frame -StartFrame $StartFrame `
    -InputPulse $InputPulse -InputDiagnostics -GameplayDiagnostics `
    -RequireAttract -RequireGameplay -RequireNoException -PcDiagnostics -PpmFile $PpmFile -PpmFrame $PpmFrame `
    -LogFile $LogFile -MilestoneFile $MilestoneFile
if ($LASTEXITCODE -ne 0) { throw 'Parent gameplay simulation failed' }
Write-Output "PASS: parent gameplay milestone reached; trace=$TraceFile"
