param(
    [Parameter(Mandatory = $true)] [string] $Executable,
	[Parameter(Mandatory = $true)] [string] $RomDir,
	[int] $MaxFrames = 2,
	[int] $MaxCycles = 0,
	[int] $TraceMax = 100000,
	[string] $TraceFile = '',
	[string] $ProducerTraceFile = '',
	[switch] $Diagnostics,
	[switch] $PixelDiagnostics,
	[switch] $PaletteDiagnostics,
	[switch] $FrameStateDiagnostics,
	[switch] $SoundDiagnostics,
	[switch] $AudioOnly,
	[switch] $AudioFmOnly,
	[switch] $Z80Diagnostics,
	[switch] $PostDiagnostics,
	[switch] $PostDiagnosticsStop,
	[switch] $PcDiagnostics,
	[switch] $PcEvery,
	[switch] $CpuDetails,
	[switch] $ExceptionDiagnostics,
	[switch] $StopOnError,
	[switch] $StopOnException,
	[int] $CoinFrame = -1,
	[int] $Coin2Frame = -1,
	[int] $StartFrame = -1,
	[int] $Button1Frame = -1,
	[int] $Button1Period = -1,
	[int] $Button1End = -1,
	[int] $Button3Frame = -1,
	[int] $Button3Period = -1,
	[int] $Button3End = -1,
	[int] $RightStart = -1,
	[int] $RightEnd = -1,
	[int] $InputPulse = 2,
	[int] $CoinPulse = -1,
	[int] $StartPulse = -1,
	[int] $Button1Pulse = -1,
	[int] $Button3Pulse = -1,
	[switch] $InputDiagnostics,
	[switch] $DipDiagnostics,
	[switch] $ResetPhase,
	[switch] $GameplayDiagnostics,
	[switch] $ObjectDiagnostics,
	[switch] $ObjectTargetDiagnostics,
	[switch] $ObjectBusDiagnostics,
	[switch] $ObjectReadDiagnostics,
	[switch] $HostBusDiagnostics,
	[switch] $ProtectionDiagnostics,
	[switch] $RequireAttract,
	[switch] $RequireGameplay,
	[switch] $RequireInLevel,
	[switch] $RequireNoException,
	[string] $PpmFile = '',
	[int] $PpmFrame = 0,
	[int] $InLevelFrame = 1400,
	[string] $PpmPrefix = '',
	[int] $PpmStart = 600,
	[int] $PpmEnd = 1400,
	[int] $PpmPeriod = 100,
	[string] $VramDumpFile = '',
	[int] $VramDumpFrame = 0,
	[string] $ObjDumpFile = '',
	[int] $ObjDumpFrame = 0,
	[string] $LogFile = '',
	[string] $MilestoneFile = '',
	[string] $ReplayP1P3Hex = '',
	[int] $ReplayP1P3Count = 0,
	[string] $SaveState = '',
	[int] $AutoSaveFrame = 1,
	[string] $RestoreState = '',
	[string] $AudioFile = '',
	[int] $AudioStartFrame = -1,
	[int] $AudioEndFrame = -1,
	[int] $HostTimeoutSeconds = 1800,
	[uint32] $Dipsw = 0x00a00000
)

$ErrorActionPreference = 'Stop'

function Get-Sha256Hex([string] $Path) {
	# Background validation also runs under the inbox Windows PowerShell host,
	# whose minimal module path may not auto-load Get-FileHash.  Use the .NET
	# primitive directly so the immutable ROM lock is enforced in every host.
	$stream = [IO.File]::OpenRead($Path)
	try {
		$sha = [Security.Cryptography.SHA256]::Create()
		try {
			return ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-', '').ToLowerInvariant()
		} finally {
			$sha.Dispose()
		}
	} finally {
		$stream.Dispose()
	}
}

# JTFRAME's J68 simulation ROMs are intentionally external to the public core
# tree.  Stage the GPL source tables beside the executable so $readmemb() is
# deterministic, without copying any game ROM or NVRAM into the repository.
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$exe = (Resolve-Path -LiteralPath $Executable).Path
$rom = (Resolve-Path -LiteralPath $RomDir).Path
$requiredRomFiles = @('main.hex', 'snd.hex', 'tile.hex', 'sprite.hex', 'pcm.hex', 'nvram.hex')
foreach ($name in $requiredRomFiles) {
	$path = Join-Path $rom $name
	if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
		throw "Missing required parent simulation image: $path. Run prepare_parent_sim_rom.py first."
	}
	if ((Get-Item -LiteralPath $path).Length -eq 0) {
		throw "Empty parent simulation image: $path"
	}
}
$manifestPath = Join-Path $rom 'parent-rom.json'
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
	throw "Missing locked parent simulation manifest: $manifestPath"
}
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
if ($manifest.set -ne 'bucky' -or
	$manifest.archive_sha256 -ne 'd9eab6109959a7a77e83871ea775954d10f0a607fa320b81d75713dc12f38987') {
	throw "Parent simulation manifest does not identify the locked bucky.zip: $manifestPath"
}
foreach ($name in $requiredRomFiles) {
	$expected = $manifest.files.$name.sha256
	$actual = Get-Sha256Hex (Join-Path $rom $name)
	if ([string]::IsNullOrWhiteSpace($expected) -or $actual -ne $expected) {
		throw "Parent simulation image hash mismatch: $name"
	}
}
$ucrtRuntime = 'C:\msys64\ucrt64\bin'
if (-not (Test-Path -LiteralPath $ucrtRuntime -PathType Container)) {
	throw "Missing UCRT64 runtime directory: $ucrtRuntime"
}
if ($HostTimeoutSeconds -lt 1) { throw 'HostTimeoutSeconds must be at least one second' }
$jtJ68 = Join-Path $root '.workbench\upstream\jtcores\modules\jtframe\hdl\cpu\j68'
$jtFx68k = Join-Path $root '.workbench\upstream\jtcores\modules\fx68k\hdl'
$runtime = Join-Path $env:TEMP "bucky-parent-runtime-$PID"
New-Item -ItemType Directory -Force -Path $runtime | Out-Null
$result = Join-Path $runtime 'result.txt'
Remove-Item -LiteralPath $result -Force -ErrorAction SilentlyContinue

foreach ($name in @('j68_dec_c.mem', 'j68_ram_c.mem')) {
	$source = Join-Path $jtJ68 $name
	if (-not (Test-Path -LiteralPath $source)) { throw "Missing JTFRAME J68 table: $source" }
	Copy-Item -LiteralPath $source -Destination (Join-Path $runtime $name) -Force
}

# The production fx68k model also loads its decode tables relative to CWD.
# Missing tables leave the decode words at zero and trigger a time-zero ALU
# assertion before the board can release reset.
foreach ($name in @('microrom.mem', 'nanorom.mem')) {
	$source = Join-Path $jtFx68k $name
	if (-not (Test-Path -LiteralPath $source)) { throw "Missing fx68k table: $source" }
	Copy-Item -LiteralPath $source -Destination (Join-Path $runtime $name) -Force
}

# These are generated arithmetic tables, not game data, and are required by
# the K054539 simulation when its $readmemh() calls are relative to CWD.
foreach ($name in @('voltab.hex', 'pantab.hex', 'rram_zero.hex')) {
	$source = Join-Path $root "cores\bucky\hdl\$name"
	Copy-Item -LiteralPath $source -Destination (Join-Path $runtime $name) -Force
}
if (Test-Path -LiteralPath (Join-Path $rom 'nvram.bin')) {
	Copy-Item -LiteralPath (Join-Path $rom 'nvram.bin') -Destination (Join-Path $runtime 'nvram.bin') -Force
}

if ([string]::IsNullOrWhiteSpace($TraceFile)) {
	$TraceFile = Join-Path $runtime 'bucky-parent.jsonl'
}
$trace = [IO.Path]::GetFullPath($TraceFile)

$plus = @(
	"+MAIN_HEX=$(Join-Path $rom 'main.hex')",
	"+SND_HEX=$(Join-Path $rom 'snd.hex')",
	"+TILE_HEX=$(Join-Path $rom 'tile.hex')",
	"+SPRITE_HEX=$(Join-Path $rom 'sprite.hex')",
	"+PCM_HEX=$(Join-Path $rom 'pcm.hex')",
	"+NVRAM_HEX=$(Join-Path $rom 'nvram.hex')",
	"+MAX_FRAMES=$MaxFrames",
	"+MAX_CYCLES=$MaxCycles",
	"+TRACE_MAX=$TraceMax",
	"+TRACE_FILE=$trace",
	"+RESULT_FILE=$result",
	"+DIPSW=$('{0:x8}' -f $Dipsw)"
)
if (-not [string]::IsNullOrWhiteSpace($ProducerTraceFile)) {
	$producerTrace = [IO.Path]::GetFullPath($ProducerTraceFile)
	$plus += "+EEP_TRACE_FILE=$producerTrace"
}
if ($Diagnostics) { $plus += '+DIAG' }
if ($PixelDiagnostics) { $plus += '+PIXDIAG' }
if ($PaletteDiagnostics) { $plus += '+PALDIAG' }
if ($FrameStateDiagnostics) { $plus += '+FRAMESTATE' }
if ($SoundDiagnostics) { $plus += '+SOUND_DIAG' }
if ($AudioOnly) { $plus += '+AUDIO_ONLY' }
if ($AudioFmOnly) { $plus += '+AUDIO_FM_ONLY' }
if ($Z80Diagnostics) { $plus += '+Z80_DIAG' }
if ($PostDiagnostics) { $plus += '+POST_DIAG' }
if ($PostDiagnosticsStop) { $plus += '+POST_DIAG_STOP' }
if ($PcDiagnostics) { $plus += '+PC_DIAG' }
if ($PcEvery) { $plus += '+PC_EVERY' }
if ($CpuDetails) { $plus += '+CPUDETAIL' }
if ($ExceptionDiagnostics) { $plus += '+EXCEPTION_DIAG' }
if ($StopOnError) { $plus += '+STOP_ON_ERROR' }
if ($StopOnException) { $plus += '+STOP_ON_EXCEPTION' }
if ($CoinFrame -ge 0) { $plus += "+COIN_FRAME=$CoinFrame" }
if ($Coin2Frame -ge 0) { $plus += "+COIN2_FRAME=$Coin2Frame" }
if ($StartFrame -ge 0) { $plus += "+START_FRAME=$StartFrame" }
if ($Button1Frame -ge 0) { $plus += "+BUTTON1_FRAME=$Button1Frame" }
if ($Button1Period -gt 0) { $plus += "+BUTTON1_PERIOD=$Button1Period" }
if ($Button1End -ge 0) { $plus += "+BUTTON1_END=$Button1End" }
if ($Button3Frame -ge 0) { $plus += "+BUTTON3_FRAME=$Button3Frame" }
if ($Button3Period -gt 0) { $plus += "+BUTTON3_PERIOD=$Button3Period" }
if ($Button3End -ge 0) { $plus += "+BUTTON3_END=$Button3End" }
if ($RightStart -ge 0) { $plus += "+RIGHT_START=$RightStart" }
if ($RightEnd -ge 0) { $plus += "+RIGHT_END=$RightEnd" }
if ($InputPulse -lt 1) { throw 'InputPulse must be at least one frame' }
if ($CoinPulse -ge 0) { $plus += "+COIN_PULSE=$CoinPulse" }
if ($StartPulse -ge 0) { $plus += "+START_PULSE=$StartPulse" }
if ($Button1Pulse -ge 0) { $plus += "+BUTTON1_PULSE=$Button1Pulse" }
if ($Button3Pulse -ge 0) { $plus += "+BUTTON3_PULSE=$Button3Pulse" }
if ($CoinFrame -ge 0 -or $Coin2Frame -ge 0 -or $StartFrame -ge 0 -or $Button1Frame -ge 0 -or $Button3Frame -ge 0) { $plus += "+INPUT_PULSE=$InputPulse" }
if ($InputDiagnostics) { $plus += '+INPUT_DIAG' }
if ($DipDiagnostics) {
	$plus += '+DIP_DIAG'
	$plus += "+DIP_EXPECT=$('{0:x}' -f (($Dipsw -shr 20) -band 0xf))"
}
if ($ResetPhase) { $plus += '+RESET_PHASE' }
if ($GameplayDiagnostics) { $plus += '+GAMEPLAY_DIAG' }
if ($ObjectDiagnostics) { $plus += '+OBJ_DIAG' }
if ($ObjectTargetDiagnostics) { $plus += '+OBJ_TARGET_DIAG' }
if ($ObjectBusDiagnostics) { $plus += '+OBJ_BUS_DIAG' }
if ($ObjectReadDiagnostics) { $plus += '+OBJ_READ_DIAG' }
if ($HostBusDiagnostics) { $plus += '+HOST_BUS_DIAG' }
if ($ProtectionDiagnostics) { $plus += '+PROT_DIAG' }
if ($RequireAttract) { $plus += '+REQUIRE_ATTRACT' }
if ($RequireGameplay) { $plus += '+REQUIRE_GAMEPLAY' }
if ($RequireInLevel) {
	$plus += '+REQUIRE_INLEVEL'
	$plus += "+INLEVEL_FRAME=$InLevelFrame"
}
if ($RequireNoException) { $plus += '+REQUIRE_NO_EXCEPTION' }
if (-not [string]::IsNullOrWhiteSpace($PpmFile)) {
	$plus += "+PPM_FILE=$([IO.Path]::GetFullPath($PpmFile))"
	$plus += "+PPM_FRAME=$PpmFrame"
}
if (-not [string]::IsNullOrWhiteSpace($PpmPrefix)) {
	$plus += "+PPM_PREFIX=$([IO.Path]::GetFullPath($PpmPrefix))"
	$plus += "+PPM_START=$PpmStart"
	$plus += "+PPM_END=$PpmEnd"
	$plus += "+PPM_PERIOD=$PpmPeriod"
}
if (-not [string]::IsNullOrWhiteSpace($VramDumpFile)) {
	$plus += "+VRAM_DUMP_FILE=$([IO.Path]::GetFullPath($VramDumpFile))"
	$plus += "+VRAM_DUMP_FRAME=$VramDumpFrame"
}
if (-not [string]::IsNullOrWhiteSpace($ObjDumpFile)) {
	$plus += "+OBJ_DUMP_FILE=$([IO.Path]::GetFullPath($ObjDumpFile))"
	$plus += "+OBJ_DUMP_FRAME=$ObjDumpFrame"
}
if (-not [string]::IsNullOrWhiteSpace($MilestoneFile)) {
	$plus += "+MILESTONE_FILE=$([IO.Path]::GetFullPath($MilestoneFile))"
}
if (-not [string]::IsNullOrWhiteSpace($ReplayP1P3Hex)) {
	$replayP1P3 = [IO.Path]::GetFullPath($ReplayP1P3Hex)
	if (-not (Test-Path -LiteralPath $replayP1P3 -PathType Leaf)) {
		throw "Missing P1/P3 replay table: $replayP1P3"
	}
	if ($ReplayP1P3Count -lt 1 -or $ReplayP1P3Count -gt 256) {
		throw 'ReplayP1P3Count must be between 1 and 256'
	}
	$plus += "+P1P3_REPLAY_HEX=$replayP1P3"
	$plus += "+P1P3_REPLAY_COUNT=$ReplayP1P3Count"
}
if (-not [string]::IsNullOrWhiteSpace($SaveState)) {
	$plus += "+SAVE_STATE=$([IO.Path]::GetFullPath($SaveState))"
	$plus += "+AUTO_SAVE_FRAME=$AutoSaveFrame"
}
if (-not [string]::IsNullOrWhiteSpace($RestoreState)) {
	$restore = [IO.Path]::GetFullPath($RestoreState)
	if (-not (Test-Path -LiteralPath $restore -PathType Leaf)) {
		throw "Missing Verilator checkpoint: $restore"
	}
	$plus += "+RESTORE_STATE=$restore"
}
if (-not [string]::IsNullOrWhiteSpace($AudioFile)) {
	$plus += "+AUDIO_FILE=$([IO.Path]::GetFullPath($AudioFile))"
	$plus += "+AUDIO_START_FRAME=$AudioStartFrame"
	$plus += "+AUDIO_END_FRAME=$AudioEndFrame"
}

$previousPath = $env:PATH
$env:PATH = "$ucrtRuntime;$previousPath"
Push-Location $runtime
try {
	# Project-owned non-SDL execution path. Use a finite host watchdog in
	# addition to the model's semantic frame/cycle stop barriers.
	$psi = [Diagnostics.ProcessStartInfo]::new()
	$psi.FileName = $exe
	$psi.WorkingDirectory = $runtime
	$psi.UseShellExecute = $false
	$psi.CreateNoWindow = $true
	$psi.RedirectStandardOutput = $true
	$psi.RedirectStandardError = $true
	# Use the Windows command-line string property for compatibility with both
	# Windows PowerShell 5.1 and PowerShell 7. Plusargs contain no embedded
	# quotes; quote each complete argument so paths with spaces remain intact.
	$psi.Arguments = (($plus | ForEach-Object {
		'"' + ([string]$_).Replace('"', '\"') + '"'
	}) -join ' ')
	$process = [Diagnostics.Process]::new()
	$process.StartInfo = $psi
	if (-not $process.Start()) { throw 'Failed to start headless parent simulation' }
	$stdoutTask = $process.StandardOutput.ReadToEndAsync()
	$stderrTask = $process.StandardError.ReadToEndAsync()
	if (-not $process.WaitForExit($HostTimeoutSeconds * 1000)) {
		$process.Kill()
		$process.WaitForExit()
		throw "Parent simulation exceeded host watchdog (${HostTimeoutSeconds}s)"
	}
	$stdout = $stdoutTask.GetAwaiter().GetResult()
	$stderr = $stderrTask.GetAwaiter().GetResult()
	$combined = $stdout + $stderr
	if (-not [string]::IsNullOrWhiteSpace($combined)) { Write-Output $combined.TrimEnd() }
	if (-not [string]::IsNullOrWhiteSpace($LogFile)) {
		$log = [IO.Path]::GetFullPath($LogFile)
		[IO.File]::WriteAllText($log, $combined)
	}
	$simExit = $process.ExitCode
	if ($simExit -ne 0) { throw "Parent simulation failed with exit code $simExit" }
} finally {
	Pop-Location
	$env:PATH = $previousPath
}

${resultPassed} = (Test-Path -LiteralPath $result) -and
	((Get-Content -LiteralPath $result -Raw).Trim() -eq 'PASS')
# A restored Verilated model necessarily carries its serialized SystemVerilog
# packed strings, including the original RESULT_FILE/TRACE_FILE paths.  The
# host wrapper cannot replace those without changing model state.  For a
# restore only, accept the testbench's exact stdout PASS marker from the
# declared log; ordinary reset runs still require the fresh result artifact.
${restoredLogPassed} = -not [string]::IsNullOrWhiteSpace($RestoreState) -and
	-not [string]::IsNullOrWhiteSpace($LogFile) -and
	(Test-Path -LiteralPath ([IO.Path]::GetFullPath($LogFile))) -and
	[bool](Select-String -LiteralPath ([IO.Path]::GetFullPath($LogFile)) `
		-Pattern '^PASS tb_bucky_parent frames=' -Quiet)
if (-not $resultPassed -and -not $restoredLogPassed) {
	throw 'Parent simulation ended without the testbench PASS marker'
}

if ([string]::IsNullOrWhiteSpace($RestoreState) -and -not (Test-Path -LiteralPath $trace)) {
	throw "Trace was not written: $trace"
}
Write-Output "PASS: parent simulation completed; trace=$trace"
