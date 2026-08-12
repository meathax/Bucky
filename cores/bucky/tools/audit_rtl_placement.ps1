param(
	[string]$StagedCore,
	[string]$GeneratedWrapper,
	[string]$MapReport,
	[switch]$RequireGenerated
)

$ErrorActionPreference = 'Stop'

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$bucky = Join-Path $root 'cores\bucky'

# This is the intentional production RTL closure. Keep it in one place so
# the source audit and generated-QIP audit agree about what Quartus may
# compile.
$productionRtl = @(
	'bucky_colmix.v', 'bucky_k053252.v', 'bucky_k054000.v',
	'bucky_k054338.v', 'bucky_k056832_romrd.v', 'bucky_main.v',
	'bucky_video.v', 'cowboys_k056832.v', 'cowboys_lyro64.v',
	'cowboys_obj.v', 'cowboys_sound.v', 'jtbucky_game.v',
	'k053246_dma.v', 'k053246_mmr.v', 'k053247.v',
	'k053247_buffer.v', 'k053247_draw.v', 'k053247_gate.v',
	'k053251.v', 'k054539.v', 'k053246.sv', 'k053246_scan.sv'
)
$disconnectedRtl = @('k053246_draw.v', 'k053246_objdraw.v', 'k053246_skid.v')
$foreignRtl = @(
	'jtsimson_obj.v', 'jtmoomesa_game.v', 'jtbuckyaa_game.v',
	'jt053246_dma.v', 'jt053246_mmr.v', 'jtcolmix_053251.v',
	'jtaliens_scroll.v', 'jt052109.v', 'jt051962.v', 'jt051960.v',
	'jtriders_dump.v', 'jtriders_sound.v',
	'jt053260.v', 'jt053260_channel.v', 'jt053260_timer.v'
)

foreach ($name in $productionRtl) {
	$path = Join-Path $bucky ("hdl\{0}" -f $name)
	if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
		throw "Production RTL is missing: $name"
	}
}

$manifest = Get-Content -Raw -LiteralPath (Join-Path $bucky 'cfg\files.yaml')
foreach ($name in $productionRtl) {
	if ($manifest -notmatch [regex]::Escape("- $name")) {
		throw "cfg/files.yaml does not list production RTL: $name"
	}
}
foreach ($name in ($disconnectedRtl + $foreignRtl)) {
	if ($manifest -match [regex]::Escape("- $name")) {
		throw "cfg/files.yaml lists disconnected or foreign RTL: $name"
	}
}

if ($RequireGenerated -and [string]::IsNullOrWhiteSpace($StagedCore)) {
	throw '-RequireGenerated needs -StagedCore pointing at jtcores/cores/bucky'
}

if (-not [string]::IsNullOrWhiteSpace($StagedCore)) {
	$staged = (Resolve-Path -LiteralPath $StagedCore).Path
	# jtcore writes target artifacts below cores/<core>/<target>. Prefer that
	# live target artifact over an older root-level staging copy.
	$generatedDir = Join-Path $staged 'mister'
	$qip = Join-Path $generatedDir 'files.qip'
	if (-not (Test-Path -LiteralPath $qip -PathType Leaf)) {
		$generatedDir = $staged
		$qip = Join-Path $staged 'files.qip'
	}
	if (-not (Test-Path -LiteralPath $qip -PathType Leaf)) {
		throw "Generated files.qip is missing: $qip"
	}
	$qipText = Get-Content -Raw -LiteralPath $qip
	foreach ($name in $productionRtl) {
		if ($qipText -notmatch [regex]::Escape($name)) {
			throw "Generated files.qip is missing production RTL: $name"
		}
	}
	foreach ($name in ($disconnectedRtl + $foreignRtl)) {
		if ($qipText -match [regex]::Escape($name)) {
			throw "Generated files.qip includes disconnected or foreign RTL: $name"
		}
	}
	$wrapper = if ([string]::IsNullOrWhiteSpace($GeneratedWrapper)) {
		Join-Path $generatedDir 'jtbucky_game_sdram.v'
	} else {
		(Resolve-Path -LiteralPath $GeneratedWrapper).Path
	}
	$ports = Join-Path $generatedDir 'mem_ports.inc'
	foreach ($path in @($wrapper, $ports)) {
		if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
			throw "Generated JTFRAME artifact is missing: $path"
		}
	}
	$wrapperText = Get-Content -Raw -LiteralPath $wrapper
	if ($wrapperText -notmatch 'cowboys_lyro64\s*#\s*\(') {
		throw 'Generated JTFRAME wrapper does not instantiate cowboys_lyro64 on the sprite bank'
	}
	if ($wrapperText -match 'jtframe_rom_1slot\s*#\s*\([\s\S]*?// lyro[\s\S]*?\)\s*u_bank3') {
		throw 'Generated JTFRAME wrapper still instantiates the stock sprite bank slot'
	}
}

if (-not [string]::IsNullOrWhiteSpace($MapReport)) {
	$map = (Resolve-Path -LiteralPath $MapReport).Path
	$mapText = Get-Content -Raw -LiteralPath $map
	if ($mapText -match '(?im)uninferred due to') {
		$hits = ([regex]::Matches($mapText, '(?im)^.*uninferred due to.*$') | ForEach-Object { $_.Value }) -join "`n"
		throw "Quartus reported memory inference failures:`n$hits"
	}
	Write-Output "PASS: Quartus map report has no 'uninferred due to' memory diagnostics ($map)"
} else {
	Write-Output 'NOTICE: no Quartus map report supplied; memory inference remains an RBF-build gate'
}

Write-Output 'PASS: Bucky production RTL/source-closure placement audit'
