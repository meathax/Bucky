param(
	[Parameter(Mandatory = $true)] [string] $RunDir,
	[string] $Mame = 'D:\Arcade\AI\mameexe\mame.exe',
	[string] $RomDir = '',
	[int] $StopFrame = 1401,
	[int] $ObjectDumpFrame = -1,
	[int] $FullObjectDumpFrame = -1,
	[switch] $ObjectWatch,
	[switch] $PlayerWatch,
	[switch] $ProducerTrace
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
if ([string]::IsNullOrWhiteSpace($RomDir)) { $RomDir = Join-Path $root 'rom' }
$mamePath = (Resolve-Path -LiteralPath $Mame).Path
$romPath = (Resolve-Path -LiteralPath $RomDir).Path
$runPath = [IO.Path]::GetFullPath($RunDir)
if (Test-Path -LiteralPath $runPath) {
	$existing = @(Get-ChildItem -LiteralPath $runPath -Force)
	if ($existing.Count -ne 0) { throw "MAME run directory must be new or empty: $runPath" }
} else {
	New-Item -ItemType Directory -Path $runPath | Out-Null
}

$cfg = New-Item -ItemType Directory -Path (Join-Path $runPath 'cfg')
$nvram = New-Item -ItemType Directory -Path (Join-Path $runPath 'nvram')
$state = New-Item -ItemType Directory -Path (Join-Path $runPath 'state')
$lua = (Resolve-Path (Join-Path $PSScriptRoot 'diff\mame_gameplay_capture.lua')).Path
$log = Join-Path $runPath 'mame-console.log'
$expectedMame = 'AF6966108D9B52C22465C6D50F4E5D50CC371B50F2D27DC443935F287AAD37A3'
$expectedRom = 'D9EAB6109959A7A77E83871EA775954D10F0A607FA320B81D75713DC12F38987'
if ((Get-FileHash -LiteralPath $mamePath -Algorithm SHA256).Hash -ne $expectedMame) {
	throw 'MAME binary hash does not match the pinned 0.289 reference'
}
if ((Get-FileHash -LiteralPath (Join-Path $romPath 'bucky.zip') -Algorithm SHA256).Hash -ne $expectedRom) {
	throw 'bucky.zip hash does not match the locked parent ROM'
}

$oldRunDir = $env:BUCKY_MAME_RUN_DIR
$oldStop = $env:BUCKY_MAME_STOP_FRAME
$oldObjectDump = $env:BUCKY_MAME_OBJ_DUMP_FRAME
$oldFullObjectDump = $env:BUCKY_MAME_OBJ_FULL_DUMP_FRAME
$oldObjectWatch = $env:BUCKY_MAME_OBJ_WATCH
$oldPlayerWatch = $env:BUCKY_MAME_PLAYER_WATCH
$oldProducerTrace = $env:BUCKY_MAME_PRODUCER_TRACE
$env:BUCKY_MAME_RUN_DIR = $runPath.Replace('\\', '/')
$env:BUCKY_MAME_STOP_FRAME = [string]$StopFrame
$env:BUCKY_MAME_OBJ_DUMP_FRAME = [string]$ObjectDumpFrame
$env:BUCKY_MAME_OBJ_FULL_DUMP_FRAME = [string]$FullObjectDumpFrame
if ($ObjectWatch) { $env:BUCKY_MAME_OBJ_WATCH = '1' } else { $env:BUCKY_MAME_OBJ_WATCH = '0' }
if ($PlayerWatch) { $env:BUCKY_MAME_PLAYER_WATCH = '1' } else { $env:BUCKY_MAME_PLAYER_WATCH = '0' }
if ($ProducerTrace) { $env:BUCKY_MAME_PRODUCER_TRACE = '1' } else { $env:BUCKY_MAME_PRODUCER_TRACE = '0' }
Push-Location $runPath
try {
	$previousErrorAction = $ErrorActionPreference
	$ErrorActionPreference = 'Continue'
	& $mamePath bucky -noreadconfig -rompath $romPath -autoboot_script $lua `
		-autoboot_delay 0 -video none -sound none -nothrottle -frameskip 0 `
		-skip_gameinfo -noplugins -nocheat -noautosave -norewind `
		-nohttp -noconsole -cfg_directory $cfg.FullName `
		-nvram_directory $nvram.FullName -state_directory $state.FullName *> $log
	$exitCode = $LASTEXITCODE
	$ErrorActionPreference = $previousErrorAction
} finally {
	Pop-Location
	$env:BUCKY_MAME_RUN_DIR = $oldRunDir
	$env:BUCKY_MAME_STOP_FRAME = $oldStop
	$env:BUCKY_MAME_OBJ_DUMP_FRAME = $oldObjectDump
	$env:BUCKY_MAME_OBJ_FULL_DUMP_FRAME = $oldFullObjectDump
	$env:BUCKY_MAME_OBJ_WATCH = $oldObjectWatch
	$env:BUCKY_MAME_PLAYER_WATCH = $oldPlayerWatch
	$env:BUCKY_MAME_PRODUCER_TRACE = $oldProducerTrace
}
if ($exitCode -ne 0) { throw "MAME gameplay capture failed with exit code $exitCode" }

$gameLog = Join-Path $runPath 'mame-gameplay.log'
$inputs = Join-Path $runPath 'applied-inputs.jsonl'
$captureFrames = @(580, 600, 700, 800, 900, 1000, 1100, 1200, 1300, 1400) |
	Where-Object { $_ -le $StopFrame }
$requiredArtifacts = @($gameLog, $inputs)
foreach ($frame in $captureFrames) {
	$requiredArtifacts += Join-Path $runPath ("frame-{0}.png" -f $frame)
}
foreach ($required in $requiredArtifacts) {
	if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "Missing MAME gameplay artifact: $required" }
}
if ($ObjectDumpFrame -ge 0) {
	$objectDump = Join-Path $runPath ("object-source-{0}.log" -f $ObjectDumpFrame)
	if (-not (Test-Path -LiteralPath $objectDump -PathType Leaf)) { throw "Missing MAME object-source artifact: $objectDump" }
}
if ($FullObjectDumpFrame -ge 0) {
	$fullObjectDump = Join-Path $runPath ("object-full-{0}.log" -f $FullObjectDumpFrame)
	if (-not (Test-Path -LiteralPath $fullObjectDump -PathType Leaf)) { throw "Missing MAME full object-source artifact: $fullObjectDump" }
}
if ($ObjectWatch) {
	$objectWatchFile = Join-Path $runPath 'object-watch.log'
	if (-not (Test-Path -LiteralPath $objectWatchFile -PathType Leaf)) { throw "Missing MAME object-watch artifact: $objectWatchFile" }
}
if ($PlayerWatch) {
	$playerWatchFile = Join-Path $runPath 'player-watch.log'
	if (-not (Test-Path -LiteralPath $playerWatchFile -PathType Leaf)) { throw "Missing MAME player-watch artifact: $playerWatchFile" }
}
if ($ProducerTrace) {
	$producerTraceFile = Join-Path $runPath 'eeprom-workram.raw.jsonl'
	if (-not (Test-Path -LiteralPath $producerTraceFile -PathType Leaf)) { throw "Missing MAME producer trace artifact: $producerTraceFile" }
}
if ((Get-Content -LiteralPath $gameLog -Tail 1) -notmatch ("^DONE frame={0} " -f $StopFrame)) {
	throw "MAME gameplay capture did not reach the frame-$StopFrame stop barrier"
}
$journal = Join-Path $root 'cores\bucky\cfg\gameplay-right.inputs.jsonl'
$appliedLines = @(Get-Content -LiteralPath $inputs)
$expectedLines = @(Get-Content -LiteralPath $journal | Where-Object {
	((ConvertFrom-Json $_).at.ordinal -le $StopFrame)
})
$journalDiff = @(Compare-Object -ReferenceObject $expectedLines -DifferenceObject $appliedLines -SyncWindow 2)
if ($appliedLines.Count -ne $expectedLines.Count -or $journalDiff.Count -ne 0) {
	throw 'MAME applied input journal differs from the pinned gameplay scenario'
}

foreach ($frame in $captureFrames) {
	$png = Join-Path $runPath ("frame-{0}.png" -f $frame)
	$ppm = Join-Path $runPath ("frame-{0}.ppm" -f $frame)
	& ffmpeg -loglevel error -y -i $png -pix_fmt rgb24 $ppm
	if ($LASTEXITCODE -ne 0) { throw "Failed to normalize MAME frame $frame to P6 PPM" }
}

$frameHashes = [ordered]@{}
foreach ($frame in $captureFrames) {
	$frameHashes[[string]$frame] = (Get-FileHash -LiteralPath (Join-Path $runPath ("frame-{0}.ppm" -f $frame)) -Algorithm SHA256).Hash.ToLowerInvariant()
}
$manifest = [ordered]@{
	schema = 'bucky-mame-gameplay-capture-v1'
	mame_version = (& $mamePath -version | Select-Object -First 1)
	mame_sha256 = $expectedMame.ToLowerInvariant()
	rom_sha256 = $expectedRom.ToLowerInvariant()
	system = 'bucky'
	stop_barrier = [ordered]@{ kind='vblank_rise'; domain='screen'; ordinal=$StopFrame; reset_epoch=1 }
	input_sha256 = (Get-FileHash -LiteralPath $inputs -Algorithm SHA256).Hash.ToLowerInvariant()
	frame_sha256 = $frameHashes
	tainted = $false
}
$manifest | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $runPath 'manifest.json') -Encoding utf8
Write-Output "PASS: deterministic MAME gameplay capture reached frame $StopFrame in $runPath"
