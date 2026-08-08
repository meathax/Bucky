$ErrorActionPreference = 'Stop'

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$bucky = Join-Path $root 'cores\bucky'

function Invoke-Checked([string]$program, [string[]]$arguments) {
	& $program @arguments
	if ($LASTEXITCODE -ne 0) {
		throw "$program failed with exit code $LASTEXITCODE"
	}
}

# This gate is intentionally parent-only and stops before Quartus/RBF work.
Invoke-Checked 'powershell' @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $bucky 'tools\validate_source.ps1'))
Invoke-Checked 'python' @((Join-Path $bucky 'tools\validate_jtframe.py'), (Join-Path $root '.workbench\upstream\jtcores\cores\bucky'))

$yosys = (Get-Command yosys -ErrorAction Stop).Source
$checks = @(
	@{ top='bucky_k053252'; files=@('cores/bucky/hdl/bucky_k053252.v') },
	@{ top='bucky_k054000'; files=@('cores/bucky/hdl/bucky_k054000.v') },
	@{ top='bucky_k054338'; files=@('cores/bucky/hdl/bucky_k054338.v') },
	@{ top='bucky_k056832_romrd'; files=@('cores/bucky/hdl/bucky_k056832_romrd.v') },
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

# A pre-hardware audit must never silently become an RBF build or accept a
# private/copyrighted artifact in the public source tree.
$buckyRbf = Get-ChildItem -LiteralPath $root -Recurse -File -ErrorAction SilentlyContinue |
	Where-Object { $_.Extension -in '.rbf', '.sof' -and $_.Name -like 'Bucky*' }
if ($buckyRbf) {
	throw "Bucky bitstream found before the RBF gate: $($buckyRbf.FullName -join ', ')"
}

Write-Output 'PASS: parent-only pre-hardware audit (no Quartus/RBF invoked)'
