# Compare the generated Quartus macro block against cores/bucky/cfg/macros.def.
#
# The build tree's bucky.qsf carries the VERILOG_MACRO list, and it is produced
# by a different jtframe step than files.qip / cfgstr.hex. Those two can be
# regenerated while the qsf stays behind, which silently compiles a stale macro
# set into the RBF. That happened once already: the qsf was four days old, so
# JTFRAME_OSD_TEST was missing (the OSD Service-mode branch in jtframe_dip.v was
# compiled out while the config string still advertised the menu entry) and the
# removed JTFRAME_BA0/1/2_LEN=64 entries were still doubling SDRAM caches.
#
# Run before any release build. Exit code 1 means the qsf must be regenerated:
#   jtframe cfgstr bucky --target=mister --output quartus
# and its sorted output substituted for the macro block.

param(
	[string]$Qsf = "$PSScriptRoot\..\..\..\.workbench\upstream\jtcores\cores\bucky\mister\bucky.qsf",
	[string]$MacrosDef = "$PSScriptRoot\..\cfg\macros.def"
)

$ErrorActionPreference = 'Stop'

foreach ($required in @($Qsf, $MacrosDef)) {
	if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
		throw "Missing input: $required"
	}
}

# macros.def is sectioned; [mister] applies to this target, [mist|sidi] does not.
$wanted = [ordered]@{}
$section = ''
foreach ($line in Get-Content -LiteralPath $MacrosDef) {
	$text = $line.Trim()
	if ($text -eq '' -or $text.StartsWith('#')) { continue }
	if ($text -match '^\[(.+)\]$') { $section = $Matches[1]; continue }
	if ($section -ne '' -and $section -ne 'mister') { continue }
	$name = ($text -split '=', 2)[0].Trim()
	$wanted[$name] = $true
}

$present = @{}
foreach ($line in Get-Content -LiteralPath $Qsf) {
	if ($line -match 'VERILOG_MACRO\s+"([^"=]+)') { $present[$Matches[1]] = $true }
}

$problems = @()

foreach ($name in $wanted.Keys) {
	if (-not $present.ContainsKey($name)) {
		$problems += "macros.def defines $name but the qsf macro block does not"
	}
}

# Only flag jtframe macros the qsf invents on its own. Many JTFRAME_* values are
# legitimate generator defaults absent from macros.def (JTFRAME_DIPBASE,
# JTFRAME_NTSC, ...), so limit the reverse check to families this core sets
# explicitly and has deliberately trimmed before.
$guarded = '^(JTFRAME_BA\d_LEN|JTFRAME_NOCROP|JTFRAME_OSD_TEST|JTFRAME_SDRAM96|JTFRAME_CLK48|JTFRAME_NO_DB15)$'
foreach ($name in $present.Keys) {
	if ($name -match $guarded -and -not $wanted.Contains($name)) {
		$problems += "qsf macro block carries $name but macros.def does not define it"
	}
}

if ($problems.Count -gt 0) {
	foreach ($problem in $problems) { Write-Output "STALE: $problem" }
	Write-Output ''
	Write-Output "Regenerate with: jtframe cfgstr bucky --target=mister --output quartus"
	exit 1
}

Write-Output 'PASS: Quartus macro block matches cores/bucky/cfg/macros.def'
