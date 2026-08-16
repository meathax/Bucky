param(
	[switch] $AudioOnly
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$build = (Get-Command verilator-safe -ErrorAction Stop).Source
$run = (Get-Command verilator-sim-safe -ErrorAction Stop).Source

function Invoke-Checked([string]$program, [string[]]$arguments) {
	& $program @arguments
	if ($LASTEXITCODE -ne 0) {
		throw "$program failed with exit code $LASTEXITCODE"
	}
}

function Test-Component([string]$name, [string]$rtl, [string]$testbench,
	[string]$topOverride = '', [string[]]$compileOptions = @(), [string[]]$simOptions = @()) {
	$top = if ([string]::IsNullOrWhiteSpace($topOverride)) { "tb_$name" } else { $topOverride }
	$mdir = Join-Path $root "obj_dir\$name"
	$rtlFiles = @((Join-Path $root $rtl))
	if ($name -like 'bucky_k054539*') {
		$rtlFiles += Join-Path $root '.workbench\upstream\jtcores\modules\jtframe\hdl\ram\jtframe_dual_ram.v'
		$rtlFiles += Join-Path $root '.workbench\upstream\jtcores\modules\jtframe\hdl\ram\jtframe_dual_ram16.v'
	}
	if ($name -eq 'k053247_buffer_shadow_epoch') {
		$rtlFiles = @(
			(Join-Path $root '.workbench\upstream\jtcores\modules\jtframe\hdl\ram\jtframe_dual_ram.v'),
			(Join-Path $root 'cores\bucky\hdl\k053247_buffer.v')
		)
	}
	if ($name -like 'cowboys_k056832_fetch_budget*') {
		$rtlFiles = @(
			(Join-Path $root '.workbench\upstream\jtcores\modules\jtframe\hdl\video\jtframe_vtimer.v'),
			(Join-Path $root '.workbench\upstream\jtcores\modules\jtframe\hdl\ram\jtframe_dual_ram.v'),
			(Join-Path $root '.workbench\upstream\jtcores\modules\jtframe\hdl\ram\jtframe_rpwp_ram.v'),
			(Join-Path $root 'cores\bucky\hdl\cowboys_k056832.v')
		)
	}
	if ($name -eq 'k053247_late_line_guard') {
		$rtlFiles = @(
			(Join-Path $root '.workbench\upstream\jtcores\modules\jtframe\hdl\jtframe_sh.v'),
			(Join-Path $root '.workbench\upstream\jtcores\modules\jtframe\hdl\ram\jtframe_dual_ram.v'),
			(Join-Path $root 'cores\bucky\hdl\k053247_draw.v'),
			(Join-Path $root 'cores\bucky\hdl\k053247_buffer.v'),
			(Join-Path $root 'cores\bucky\hdl\k053247_gate.v')
		)
	}
	New-Item -ItemType Directory -Force -Path $mdir | Out-Null
	$args = @(
		# Verilator 5 rejects --timing together with --savable.  These small
		# clocked component benches use timing, while the full-core harness is
		# the savable/checkpointed model required by the debug workflow.
		'--binary', '--timing', '--threads', '1', '-Wall', '-Wno-fatal',
		# The current MSYS2/UCRT Verilator runtime is built with the legacy
		# libstdc++ ABI.  Keep this explicit so the checked-in runner links
		# identically from PowerShell and from the documented UCRT shell.
		'-CFLAGS', '-D_GLIBCXX_USE_CXX11_ABI=0',
		'--top-module', $top, '--Mdir', $mdir, '--build', '-j', '4'
	)
	$args += $rtlFiles
	$args += Join-Path $root $testbench
	$args += $compileOptions
	Invoke-Checked $build $args
	$exe = Join-Path $mdir "V$top.exe"
	if (-not (Test-Path -LiteralPath $exe)) { $exe = Join-Path $mdir "V$top" }
	if (-not (Test-Path -LiteralPath $exe)) { throw "Missing Verilator executable: $exe" }
	# k054539's generated volume/pan/reverb images are kept beside the RTL;
	# run that bench from the same directory so $readmemh resolves identically
	# to the JTFRAME core build.
	$simCwd = (Get-Location).Path
	try {
		if ($name -like 'bucky_k054539*') { Set-Location (Join-Path $root 'cores\bucky\hdl') }
		Invoke-Checked $run (@($exe) + $simOptions)
	}
	finally { Set-Location $simCwd }
}

if (-not $AudioOnly) {
	Test-Component 'bucky_k054000' 'cores\bucky\hdl\bucky_k054000.v' 'cores\bucky\hdl\sim\tb_bucky_k054000.sv'
	Test-Component 'bucky_k054338' 'cores\bucky\hdl\bucky_k054338.v' 'cores\bucky\hdl\sim\tb_bucky_k054338.sv'
	Test-Component 'bucky_k053252' 'cores\bucky\hdl\bucky_k053252.v' 'cores\bucky\hdl\sim\tb_bucky_k053252.sv'
	Test-Component 'bucky_k056832_romrd' 'cores\bucky\hdl\bucky_k056832_romrd.v' 'cores\bucky\hdl\sim\tb_bucky_k056832_romrd.sv'
	Test-Component 'cowboys_lyro64' 'cores\bucky\hdl\cowboys_lyro64.v' 'cores\bucky\hdl\sim\tb_cowboys_lyro64.sv'
	Test-Component 'bucky_k053251_shadow' 'cores\bucky\hdl\k053251.v' 'cores\bucky\hdl\sim\tb_bucky_k053251_shadow.sv'
	Test-Component 'k053247_buffer_shadow_epoch' 'cores\bucky\hdl\k053247_buffer.v' 'cores\bucky\hdl\sim\tb_k053247_buffer_shadow_epoch.sv'
	Test-Component 'k053247_late_line_guard' 'cores\bucky\hdl\k053247_gate.v' 'cores\bucky\hdl\sim\tb_k053247_late_line_guard.sv'
	Test-Component 'cowboys_k056832_fetch_budget' 'cores\bucky\hdl\cowboys_k056832.v' 'cores\bucky\hdl\sim\tb_cowboys_k056832_fetch_budget.sv'
	# The default 48 MHz run deliberately preserves the historical deficiency
	# (latencies 8/12/20 are short).  The JTFRAME_SDRAM96 variant is a separate
	# strict gate: every fixed latency through 20 and the sparse mixed-stall
	# profile must complete all 196 reads without stale pixels.
	Test-Component 'cowboys_k056832_fetch_budget_96' 'cores\bucky\hdl\cowboys_k056832.v' 'cores\bucky\hdl\sim\tb_cowboys_k056832_fetch_budget.sv' `
		'tb_cowboys_k056832_fetch_budget' @('-GCLKDIV=12') @('+MIXED_STALL')
	Test-Component 'jtframe_service_test' '.workbench\upstream\jtcores\modules\jtframe\hdl\keyboard\jtframe_joysticks.v' 'cores\bucky\hdl\sim\tb_jtframe_service_test.sv' `
		'tb_jtframe_service_test'
}
Test-Component 'bucky_download_layout' '.workbench\upstream\jtcores\modules\jtframe\hdl\sdram\jtframe_dwnld.v' 'cores\bucky\hdl\sim\tb_bucky_download_layout.sv'
Test-Component 'bucky_k054539' 'cores\bucky\hdl\k054539.v' 'cores\bucky\hdl\sim\tb_bucky_k054539.sv'
Test-Component 'bucky_k054539_keyon_mix_collision' 'cores\bucky\hdl\k054539.v' 'cores\bucky\hdl\sim\tb_bucky_k054539_keyon_mix_collision.sv'
Test-Component 'bucky_k054539_keyon_eof_collision' 'cores\bucky\hdl\k054539.v' 'cores\bucky\hdl\sim\tb_bucky_k054539_keyon_eof_collision.sv'
Test-Component 'bucky_k054539_write_release' 'cores\bucky\hdl\k054539.v' 'cores\bucky\hdl\sim\tb_bucky_k054539_write_release.sv'
Test-Component 'bucky_k054539_gated_rom' 'cores\bucky\hdl\k054539.v' 'cores\bucky\hdl\sim\tb_bucky_k054539_gated_rom.sv'
Test-Component 'bucky_k054539_reverb_rmw' 'cores\bucky\hdl\k054539.v' 'cores\bucky\hdl\sim\tb_bucky_k054539_reverb_rmw.sv'
Test-Component 'bucky_k054539_deadline' 'cores\bucky\hdl\k054539.v' 'cores\bucky\hdl\sim\tb_bucky_k054539_deadline.sv'
if ($AudioOnly) {
	Write-Output 'PASS: strict K054539 component tests'
} else {
	Write-Output 'PASS: strict video, sprite-priority/ownership, sprite-cache and K054539 component tests'
}
