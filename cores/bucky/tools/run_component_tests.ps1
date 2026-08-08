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

function Test-Component([string]$name, [string]$rtl, [string]$testbench) {
	$top = "tb_$name"
	$mdir = Join-Path $root "obj_dir\$name"
	New-Item -ItemType Directory -Force -Path $mdir | Out-Null
	Invoke-Checked $build @(
		# Verilator 5 rejects --timing together with --savable.  These small
		# clocked component benches use timing, while the full-core harness is
		# the savable/checkpointed model required by the debug workflow.
		'--binary', '--timing', '-Wall', '-Wno-fatal',
		'--top-module', $top, '--Mdir', $mdir, '--build', '-j', '0',
		(Join-Path $root $rtl), (Join-Path $root $testbench)
	)
	$exe = Join-Path $mdir "V$top.exe"
	if (-not (Test-Path -LiteralPath $exe)) { $exe = Join-Path $mdir "V$top" }
	if (-not (Test-Path -LiteralPath $exe)) { throw "Missing Verilator executable: $exe" }
	Invoke-Checked $run @($exe)
}

Test-Component 'bucky_k054000' 'cores\bucky\hdl\bucky_k054000.v' 'cores\bucky\hdl\sim\tb_bucky_k054000.sv'
Test-Component 'bucky_k054338' 'cores\bucky\hdl\bucky_k054338.v' 'cores\bucky\hdl\sim\tb_bucky_k054338.sv'
Test-Component 'bucky_k053252' 'cores\bucky\hdl\bucky_k053252.v' 'cores\bucky\hdl\sim\tb_bucky_k053252.sv'
Test-Component 'bucky_k056832_romrd' 'cores\bucky\hdl\bucky_k056832_romrd.v' 'cores\bucky\hdl\sim\tb_bucky_k056832_romrd.sv'
Write-Output 'PASS: strict K053252, K054000, K054338 and K056832 ROMRD component tests'
