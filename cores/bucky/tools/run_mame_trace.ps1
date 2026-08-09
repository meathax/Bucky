param(
    [string] $Mame = 'D:\Arcade\AI\mameexe\mame.exe',
    [Parameter(Mandatory = $true)] [string] $RomDir,
    [Parameter(Mandatory = $true)] [string] $WorkDir,
    [int] $Seconds = 1,
    [string] $Output = ''
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $Mame)) { throw "MAME executable not found: $Mame" }
$romPath = (Resolve-Path -LiteralPath $RomDir).Path
$work = [IO.Path]::GetFullPath($WorkDir)
New-Item -ItemType Directory -Force -Path $work | Out-Null
$trace = Join-Path $work 'mame-trace.jsonl'
Remove-Item -LiteralPath $trace -Force -ErrorAction SilentlyContinue
$log = Join-Path $work 'mame.log'
$lua = Join-Path $PSScriptRoot 'diff\mame_bus_trace.lua'

Push-Location $work
try {
    # MAME reports optional host-device/XInput probes on stderr even when the
    # emulation exits successfully.  Do not mistake those diagnostics for a
    # failed trace; the explicit exit-code check below is authoritative.
    $previousErrorAction = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    & $Mame bucky `
        -rompath $romPath `
        -autoboot_script $lua `
        -seconds_to_run $Seconds `
        -video none -sound none -nothrottle -skip_gameinfo -window `
        -cfg_directory $work -nvram_directory $work *> $log
    $mameExit = $LASTEXITCODE
    $ErrorActionPreference = $previousErrorAction
    if ($mameExit -ne 0) { throw "MAME trace run failed with exit code $mameExit" }
}
finally { Pop-Location }

if (-not (Test-Path -LiteralPath $trace)) { throw "MAME trace was not written: $trace" }
$lineCount = (Get-Content -LiteralPath $trace | Measure-Object -Line).Lines
if ($lineCount -lt 1) { throw "MAME trace is empty: $trace" }

if (-not [string]::IsNullOrWhiteSpace($Output)) {
    $destination = [IO.Path]::GetFullPath($Output)
    Copy-Item -LiteralPath $trace -Destination $destination -Force
    $trace = $destination
}
Write-Output "PASS: MAME parent trace events=$lineCount file=$trace"
