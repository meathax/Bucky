param(
    [Parameter(Mandatory = $true)] [string] $Executable,
    [Parameter(Mandatory = $true)] [string] $RomDir,
    [int] $MaxFrames = 600,
    # The parent bench samples the cabinet input on the falling-LVBL edge,
    # but the 68000 observes the updated port during the following bus phase.
    # The empirically locked MAME-equivalent callback values are therefore
    # retained here (coin=470, start=510, Button 1=550).
    [int] $CoinFrame = 470,
    [int] $Coin2Frame = -1,
    [int] $StartFrame = 510,
    [int] $Button1Frame = 550,
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

# This is the parent-only gameplay gate.  These defaults are the locked MAME
# callback schedule: one credit pulse after attract, followed by one-player
# start and Button 1.  MAME 0.289 reaches accepted start at frame 513 and the
# gameplay worker at frame 518; the bench must drive the corresponding callback
# values at 470/510/550 for its CPU sampling phase.
& (Join-Path $root 'cores\bucky\tools\run_parent_sim.ps1') `
    -Executable $Executable -RomDir $resolvedRomDir -MaxFrames $MaxFrames -TraceMax 1 `
    -TraceFile $TraceFile -CoinFrame $CoinFrame -Coin2Frame $Coin2Frame -StartFrame $StartFrame `
    -InputPulse $InputPulse -InputDiagnostics -GameplayDiagnostics `
    -Button1Frame $Button1Frame `
    -RequireAttract -RequireGameplay -RequireNoException -PcDiagnostics -PpmFile $PpmFile -PpmFrame $PpmFrame `
    -LogFile $LogFile -MilestoneFile $MilestoneFile
if ($LASTEXITCODE -ne 0) { throw 'Parent gameplay simulation failed' }
Write-Output "PASS: parent gameplay milestone reached; trace=$TraceFile"
