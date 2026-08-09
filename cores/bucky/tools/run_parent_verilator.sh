#!/usr/bin/env bash
set -euo pipefail

# Full parent-only JTFRAME integration build.  This script intentionally
# stops at Verilator; Quartus/RBF work is a separate release gate.
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
jtroot="$root/.workbench/upstream/jtcores"
mdir="${1:-$root/obj_dir/bucky_parent_full}"
build_jobs="${VERILATOR_BUILD_JOBS:-0}"
sim_cpu="${BUCKY_SIM_CPU:-fx68k}"

case "$sim_cpu" in
    fx68k) ;;
    j68) ;;
    *) echo "Unsupported BUCKY_SIM_CPU=$sim_cpu (expected fx68k or j68)" >&2; exit 2 ;;
esac

# The upstream workbench wrapper predates the current core mem.yaml.  Keep it
# immutable and create a checked derived copy containing main.cache_size=8;
# a normal JTFRAME regeneration emits the same CACHE1_SIZE parameter.
generated_sdram="$root/.workbench/generated/jtbucky_game_sdram.v"
python "$root/cores/bucky/tools/prepare_bucky_sdram.py" \
    "$jtroot/cores/bucky/mister/jtbucky_game_sdram.v" "$generated_sdram"

# The safe Verilator wrapper is a native Windows executable.  Convert all
# paths assembled by the MSYS shell before passing them to it; otherwise a
# `/d/...` path is treated as a literal filename on the Windows side.
native_path() {
    cygpath -w "$1"
}

mapfile -t qip_sources < <(
    grep -E '(^| )((SYSTEM)?VERILOG)_FILE ' "$jtroot/cores/bucky/files.qip" |
    sed -E 's/.* (.*)$/\1/' |
    sed 's#\\#/#g' |
    while IFS= read -r path; do
        case "$path" in
            *.vhd|*.VHDL) continue ;;
            *"/cores/bucky/jtbucky_game_sdram.v") continue ;;
            *"/cores/bucky/hdl/"*)
                printf '%s/cores/bucky/hdl/%s\n' "$root" "${path##*/cores/bucky/hdl/}" ;;
            *"/jtcores/"*)
                printf '%s/%s\n' "$root/.workbench/upstream/jtcores" "${path##*/jtcores/}" ;;
        esac
    done | sort -u
)

# fx68k ships an upstream Verilator-specific source set with explicit case
# defaults and tool-compatible process forms.  Keep Quartus on the QIP files,
# but substitute those three simulation equivalents here.
if [[ "$sim_cpu" == fx68k ]]; then
    for i in "${!qip_sources[@]}"; do
        case "${qip_sources[$i]}" in
            */modules/fx68k/hdl/fx68k.sv|*/modules/fx68k/hdl/fx68kAlu.sv|*/modules/fx68k/hdl/uaddrPla.sv)
                qip_sources[$i]="${qip_sources[$i]%/*}/verilator/${qip_sources[$i]##*/}"
                ;;
        esac
    done
fi

sources=(
    "$(native_path "$generated_sdram")"
    "$(native_path "$root/.workbench/upstream/jtcores/modules/jtframe/hdl/cpu/t80/T80s.v")"
    "$(native_path "$root/cores/bucky/tools/diff/mister_bus_trace.sv")"
    "$(native_path "$root/cores/bucky/rtl/sim/bucky_main_trace_bind.sv")"
    "$(native_path "$root/cores/bucky/hdl/sim/tb_bucky_parent.sv")"
)
for source in "${qip_sources[@]}"; do
    sources+=("$(native_path "$source")")
done

defs=(
    -DSIMULATION -DJTFRAME_MEMGEN
    -DGAMETOP=jtbucky_game_sdram -DJTFRAME_CLK48 -DJTFRAME_MCLK=48000
    -DJTFRAME_DIALEMU_LEFT=0 -DJTFRAME_PXLCLK=8 -DJTFRAME_COLORW=8
    -DJTFRAME_BUTTONS=3 -DJTFRAME_WIDTH=384 -DJTFRAME_HEIGHT=224
    -DJTFRAME_STEREO -DJTFRAME_RELEASE -DJTFRAME_HEADER=16
    # The DE10 SDRAM path is 64-bit burst based.  Every generated ROM/RAM
    # cache must see the four 16-bit return beats; omitting BA0/1/2 leaves
    # the cache half-filled and corrupts the very first 68000 reset vector.
    -DJTFRAME_BA0_LEN=64 -DJTFRAME_BA1_LEN=64 -DJTFRAME_BA2_LEN=64
    -DJTFRAME_BA3_LEN=64 -DJTFRAME_IOCTL_RD=128
    -DJTFRAME_TIMESTAMP=0 -DJTFRAME_LF_HW=1 -DJTFRAME_LF_VW=1
    -DJTFRAME_MR_FASTIO=0 -DSND_RAMW=13
)

# Match the production core by default: without JTFRAME_J68, jtframe_m68k
# instantiates fx68k.  J68 is useful for targeted diagnostics but must not be
# the acceptance CPU because an implementation-specific exception can be
# mistaken for a GX173/core bus defect.
case "$sim_cpu" in
    fx68k) ;;
    j68) defs+=( -DJTFRAME_J68 ) ;;
esac

includes=(
    "-I$(native_path "$root/.workbench/upstream/jtcores/modules/jtframe/hdl/inc")"
    "-I$(native_path "$root/.workbench/upstream/jtcores/cores/bucky/mister")"
    "-I$(native_path "$root/cores/bucky/hdl")"
    "-I$(native_path "$root/.workbench/upstream/jtcores/modules/jtframe/hdl/cpu/t80")"
    "-I$(native_path 'C:/Users/meath/AppData/Local/Temp/bucky-j68-elab')"
)

# Verilator 5.050 rejects --savable together with this event/timing bench.
# Keep the strict single-threaded correctness model until the bench moves to
# an untimed C++ clock driver with VerilatedSave/VerilatedRestore support.
verilator-safe --binary --timing --threads 1 -O3 -Wno-fatal \
    --top-module tb_bucky_parent --Mdir "$(native_path "$mdir")" --build -j "$build_jobs" \
    --output-split 20000 \
    -CFLAGS '-O3 -march=native -D_GLIBCXX_USE_CXX11_ABI=0' \
    "${defs[@]}" "${includes[@]}" "${sources[@]}"
