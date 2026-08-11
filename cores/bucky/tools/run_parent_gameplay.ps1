param(
    [Parameter(Mandatory = $true)] [string] $Executable,
    [Parameter(Mandatory = $true)] [string] $RomDir,
    [int] $MaxFrames = 1401,
    # The parent bench samples the cabinet input on the falling-LVBL edge,
    # but the 68000 observes the updated port during the following bus phase.
    # The empirically locked MAME-equivalent callback values are therefore
    # retained here (coin=470, start=510, Button 1=550).
    [int] $CoinFrame = 470,
    [int] $Coin2Frame = -1,
    [int] $StartFrame = 510,
    [int] $Button1Frame = 550,
    [int] $Button1Period = 50,
    [int] $Button1End = 1400,
    [int] $RightStart = 1200,
    [int] $RightEnd = 1400,
    [int] $CoinPulse = 20,
    [int] $StartPulse = 20,
    [int] $Button1Pulse = 1,
    [string] $TraceFile = '',
    [string] $PpmFile = '',
    [int] $PpmFrame = 1400,
    [string] $PpmPrefix = '',
    [string] $LogFile = '',
    [string] $MilestoneFile = '',
    [string] $SaveState = '',
    [int] $AutoSaveFrame = 450,
    [string] $RestoreState = ''
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$resolvedRomDir = (Resolve-Path -LiteralPath $RomDir).Path
if ([string]::IsNullOrWhiteSpace($TraceFile)) {
    $TraceFile = Join-Path $env:TEMP 'bucky-parent-gameplay.jsonl'
}
if ([string]::IsNullOrWhiteSpace($PpmFile)) {
    $PpmFile = Join-Path $env:TEMP 'bucky-parent-live-combat.ppm'
}

# This is the parent-only gameplay gate.  These defaults are the locked MAME
# callback schedule: one credit pulse after attract, one-player start, repeated
# Button 1 presses to advance the cutscene, then Right in the first combat
# scene.  The early worker PC remains diagnostic; acceptance requires the raw
# frame-1400 capture after the complete declared input journal.
& (Join-Path $root 'cores\bucky\tools\run_parent_sim.ps1') `
    -Executable $Executable -RomDir $resolvedRomDir -MaxFrames $MaxFrames -TraceMax 1 `
    -TraceFile $TraceFile -CoinFrame $CoinFrame -Coin2Frame $Coin2Frame -StartFrame $StartFrame `
    -CoinPulse $CoinPulse -StartPulse $StartPulse -Button1Pulse $Button1Pulse `
    -InputDiagnostics -GameplayDiagnostics -Button1Frame $Button1Frame `
    -Button1Period $Button1Period -Button1End $Button1End `
    -RightStart $RightStart -RightEnd $RightEnd `
    -RequireAttract -RequireGameplay -RequireInLevel -RequireNoException `
    -InLevelFrame $PpmFrame -PcDiagnostics -PpmFile $PpmFile -PpmFrame $PpmFrame `
    -PpmPrefix $PpmPrefix -PpmStart 600 -PpmEnd 1400 -PpmPeriod 100 `
    -LogFile $LogFile -MilestoneFile $MilestoneFile `
    -SaveState $SaveState -AutoSaveFrame $AutoSaveFrame -RestoreState $RestoreState
if ($LASTEXITCODE -ne 0) { throw 'Parent gameplay simulation failed' }
Write-Output "PASS: parent live-combat frame reached; ppm=$PpmFile trace=$TraceFile"
