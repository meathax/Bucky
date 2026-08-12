param(
	[Parameter(Mandatory = $true)] [string] $RunDir,
	[string] $Mame = 'D:\Arcade\AI\mameexe\mame.exe',
	[string] $RomDir = '',
	[int] $StopFrame = 2200
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
$lua = (Resolve-Path (Join-Path $PSScriptRoot 'diff\mame_backdrop_probe.lua')).Path
$consoleLog = Join-Path $runPath 'mame-console.log'
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
$env:BUCKY_MAME_RUN_DIR = $runPath.Replace('\', '/')
$env:BUCKY_MAME_STOP_FRAME = [string]$StopFrame
Push-Location $runPath
try {
	$previousErrorAction = $ErrorActionPreference
	$ErrorActionPreference = 'Continue'
	& $mamePath bucky -noreadconfig -rompath $romPath -autoboot_script $lua `
		-autoboot_delay 0 -video none -sound none -nothrottle -frameskip 0 `
		-skip_gameinfo -noplugins -nocheat -noautosave -norewind `
		-nohttp -noconsole -cfg_directory $cfg.FullName `
		-nvram_directory $nvram.FullName -state_directory $state.FullName *> $consoleLog
	$exitCode = $LASTEXITCODE
	$ErrorActionPreference = $previousErrorAction
} finally {
	Pop-Location
	$env:BUCKY_MAME_RUN_DIR = $oldRunDir
	$env:BUCKY_MAME_STOP_FRAME = $oldStop
}
if ($exitCode -ne 0) { throw "MAME backdrop probe failed with exit code $exitCode" }

$backdropLog = Join-Path $runPath 'backdrop.log'
$inputs = Join-Path $runPath 'applied-inputs.jsonl'
foreach ($required in @($backdropLog, $inputs)) {
	if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
		throw "Missing MAME backdrop artifact: $required"
	}
}
if ((Get-Content -LiteralPath $backdropLog -Tail 1) -notmatch ("^DONE frame={0} " -f $StopFrame)) {
	throw "MAME backdrop probe did not reach the frame-$StopFrame stop barrier"
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

$manifest = [ordered]@{
	schema = 'bucky-mame-backdrop-probe-v1'
	mame_version = (& $mamePath -version | Select-Object -First 1)
	mame_sha256 = $expectedMame.ToLowerInvariant()
	rom_sha256 = $expectedRom.ToLowerInvariant()
	system = 'bucky'
	stop_barrier = [ordered]@{ kind='vblank_rise'; domain='screen'; ordinal=$StopFrame; reset_epoch=1 }
	input_sha256 = (Get-FileHash -LiteralPath $inputs -Algorithm SHA256).Hash.ToLowerInvariant()
	backdrop_log_sha256 = (Get-FileHash -LiteralPath $backdropLog -Algorithm SHA256).Hash.ToLowerInvariant()
	tainted = $false
}
$manifest | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $runPath 'manifest.json') -Encoding utf8
Write-Output "PASS: deterministic MAME backdrop probe reached frame $StopFrame in $runPath"
