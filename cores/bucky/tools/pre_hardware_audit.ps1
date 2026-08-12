$ErrorActionPreference = 'Stop'

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$bucky = Join-Path $root 'cores\bucky'
$mameMap = 'D:\Arcade\AI\mame289\src\mame\konami\moo.cpp'

function Invoke-Checked([string]$program, [string[]]$arguments) {
	& $program @arguments
	if ($LASTEXITCODE -ne 0) {
		throw "$program failed with exit code $LASTEXITCODE"
	}
}

# This gate is intentionally parent-only and stops before Quartus/RBF work.
Invoke-Checked 'powershell' @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $bucky 'tools\validate_source.ps1'))
Invoke-Checked 'powershell' @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $bucky 'tools\audit_rtl_placement.ps1'))
$stagedCore = Join-Path $root '.workbench\upstream\jtcores\cores\bucky'
$generatedWrapper = Join-Path $root '.workbench\generated\jtbucky_game_sdram.v'
Invoke-Checked 'python' @(
	(Join-Path $bucky 'tools\prepare_bucky_sdram.py'),
	(Join-Path $stagedCore 'mister\jtbucky_game_sdram.v'),
	$generatedWrapper
)
Invoke-Checked 'python' @((Join-Path $bucky 'tools\validate_jtframe.py'), $stagedCore, $generatedWrapper)

$yosys = (Get-Command yosys -ErrorAction Stop).Source
$checks = @(
	@{ top='bucky_k053252'; files=@('cores/bucky/hdl/bucky_k053252.v') },
	@{ top='bucky_k054000'; files=@('cores/bucky/hdl/bucky_k054000.v') },
	@{ top='bucky_k054338'; files=@('cores/bucky/hdl/bucky_k054338.v') },
	@{ top='bucky_k056832_romrd'; files=@('cores/bucky/hdl/bucky_k056832_romrd.v') },
	@{ top='k053251'; files=@('cores/bucky/hdl/k053251.v') },
	@{ top='k054539'; files=@('cores/bucky/hdl/k054539.v') }
)

foreach ($check in $checks) {
	$read = ($check.files -join ' ')
	$script = "read_verilog -sv $read; hierarchy -top $($check.top); proc; opt; check"
	Invoke-Checked $yosys @('-Q', '-p', $script)
}

# The color mixer depends on JTFRAME's dual-RAM and delay primitives.  Parse it
# here for syntax, while leaving dependency-closure elaboration to the JTFRAME
# source/QIP validator above; isolated Yosys would otherwise report expected
# undriven black-box outputs as false functional failures.
Invoke-Checked $yosys @('-Q', '-p', 'read_verilog -sv cores/bucky/hdl/bucky_colmix.v')

# Parse the full main-map port shell without instantiating external JTFRAME cells.
Invoke-Checked $yosys @('-Q', '-p', 'read_verilog -sv -D NOMAIN cores/bucky/hdl/bucky_main.v; hierarchy -top bucky_main; proc; opt; check')
# Also parse the synthesizable CPU/blitter branch.  NOMAIN intentionally skips
# that branch, so this catches syntax/width regressions in the parent POST path.
Invoke-Checked $yosys @('-Q', '-p', 'read_verilog -sv cores/bucky/hdl/bucky_main.v')

# Keep the parent protection path tied to the published GX173 map.  This is a
# cheap guard against the common regression where the `a+2*b` datapath remains
# intact but one of the mapped RAM windows silently falls through to open bus.
$mainText = Get-Content -Raw (Join-Path $bucky 'hdl\bucky_main.v')
foreach ($pattern in @(
	'wire blt_isvram',
	'wire blt_ispal',
	'blt_isvram \? \(vdtac',
	'blt_isvram \? vram_dout',
	"blt_addr_r\[23:14\]==10'h060",
	"blt_addr_r\[23:14\]==10'h06c",
	'assign dtac_mux = .*pal_wait',
	'alpha_dout',
	'pcu_dout'
)) {
	if ($mainText -notmatch $pattern) { throw "Parent blitter contract missing: $pattern" }
}
$colmixText = Get-Content -Raw (Join-Path $bucky 'hdl\bucky_colmix.v')
if ($colmixText -notmatch 'assign pal_wait = pal_cs .*k338_cpu_priority') {
	throw 'K054338 palette arbitration contract missing'
}
if (-not (Test-Path -LiteralPath $mameMap)) { throw "MAME source map missing: $mameMap" }
$mameText = Get-Content -Raw -LiteralPath $mameMap
foreach ($pattern in @(
	'map\(0x000000, 0x07ffff\)\.rom',
	'map\(0x080000, 0x08ffff\)\.ram',
	'map\(0x090000, 0x09ffff\)\.ram\(\)\.share\(m_spriteram\)',
	'map\(0x0a0000, 0x0affff\)\.ram',
	'map\(0x0c0000, 0x0c003f\)\.w\(m_k056832',
	'map\(0x0c2000, 0x0c2007\)\.w\(m_k053246',
	'map\(0x0c4000, 0x0c4001\)\.r\(m_k053246',
	'map\(0x180000, 0x181fff\).*k056832_device::ram_word_r',
	'map\(0x184000, 0x187fff\)\.ram',
	'map\(0x190000, 0x191fff\)\.r\(m_k056832',
	'map\(0x1b0000, 0x1b3fff\).*palette',
	'map\(0x200000, 0x23ffff\)\.rom',
	'map\(0x0ca000, 0x0ca01f\)\.r\(m_k054338',
	'map\(0x0cc000, 0x0cc01f\).*k053251',
	'map\(0x0ce000, 0x0ce01f\).*moo_prot_w',
	'map\(0x0d0000, 0x0d001f\).*k053252',
	'map\(0x0d2000, 0x0d203f\).*k054000',
	'map\(0x0d4000, 0x0d4001\).*sound_irq_w',
	'map\(0x0d6000, 0x0d601f\).*k054321',
	'map\(0x0d8000, 0x0d8007\).*b_word_w',
	'map\(0x0da000, 0x0da001\)\.portr\("P1_P3"\)',
	'map\(0x0da002, 0x0da003\)\.portr\("P2_P4"\)',
	'map\(0x0dc000, 0x0dc001\)\.portr\("IN0"\)',
	'map\(0x0dc002, 0x0dc003\)\.portr\("IN1"\)',
	'map\(0x0de000, 0x0de001\).*control2',
	'map\(0x180000, 0x181fff\)\.mirror\(0x002000\)'
)) {
	if ($mameText -notmatch $pattern) { throw "MAME parent map contract missing: $pattern" }
}

# A pre-hardware audit must never silently become an RBF build or accept a
# private/copyrighted artifact in the public source tree.
$buckyRbf = Get-ChildItem -LiteralPath $root -Recurse -File -ErrorAction SilentlyContinue |
	Where-Object { $_.Extension -in '.rbf', '.sof' -and $_.Name -like 'Bucky*' }
if ($buckyRbf) {
	throw "Bucky bitstream found before the RBF gate: $($buckyRbf.FullName -join ', ')"
}

Write-Output 'PASS: parent-only pre-hardware audit (no Quartus/RBF invoked)'
