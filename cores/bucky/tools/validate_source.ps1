$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path

$required = @(
	'cores\bucky\hdl\jtbucky_game.v',
	'cores\bucky\hdl\bucky_main.v',
	'cores\bucky\hdl\bucky_video.v',
	'cores\bucky\hdl\bucky_colmix.v',
	'cores\bucky\hdl\bucky_k054000.v',
	'cores\bucky\hdl\bucky_k054338.v',
	'cores\bucky\cfg\mame2mra.toml'
)
foreach ($relative in $required) {
	if (-not (Test-Path -LiteralPath (Join-Path $root $relative))) {
		throw "Missing required source: $relative"
	}
}

$forbidden = Get-ChildItem -LiteralPath (Join-Path $root 'cores\bucky') -Recurse -File |
	Where-Object { $_.FullName -match 'SiliconRE|054000_trace|k054000_schematics|054338_schematic' }
if ($forbidden) {
	throw "SiliconRE evidence entered compiled/public source: $($forbidden.FullName -join ', ')"
}

$private = Get-ChildItem -LiteralPath (Join-Path $root 'cores\bucky') -Recurse -File |
	Where-Object { $_.Extension -in '.zip', '.rom', '.bin' }
if ($private) {
	throw "Private ROM artifact entered core tree: $($private.FullName -join ', ')"
}

& python (Join-Path $root 'cores\bucky\tools\validate_mra.py') (Join-Path $root 'cores\bucky\releases')
if ($LASTEXITCODE -ne 0) { throw 'MRA validation failed' }

$romHash = (Get-FileHash -LiteralPath (Join-Path $root 'rom\bucky.zip') -Algorithm SHA256).Hash
if ($romHash -ne 'D9EAB6109959A7A77E83871EA775954D10F0A607FA320B81D75713DC12F38987') {
	throw "Unexpected private ROM archive hash: $romHash"
}

Write-Output 'PASS: Bucky source/provenance gate'
