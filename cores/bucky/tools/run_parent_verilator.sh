#!/usr/bin/env bash
set -euo pipefail

# Full parent-only JTFRAME integration build.  This script intentionally
# stops at Verilator; Quartus/RBF work is a separate release gate.
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
jtroot="$root/.workbench/upstream/jtcores"
mdir="${1:-$root/obj_dir/bucky_parent_full}"
build_jobs="${VERILATOR_BUILD_JOBS:-4}"
sim_cpu="${BUCKY_SIM_CPU:-fx68k}"
sim_fast="${BUCKY_SIM_FAST:-0}"
sim_skip_erase="${BUCKY_SIM_SKIP_ERASE:-0}"
sim_savable="${BUCKY_SIM_SAVABLE:-0}"
sim_lto="${BUCKY_SIM_LTO:-0}"
sim_output_split="${BUCKY_SIM_OUTPUT_SPLIT:-20000}"

# MSYS2's login PATH intentionally omits the Windows user-bin directory.  Use
# the machine-wide guarded launcher by absolute path when command lookup does
# not find it; falling back to an unguarded Verilator would break the project
# contract.
safe_verilator="$(command -v verilator-safe || true)"
if [[ -z "$safe_verilator" ]]; then
    safe_verilator="/c/Users/meath/bin/verilator-safe.exe"
fi
if [[ ! -x "$safe_verilator" ]]; then
    echo "Missing machine-wide safe Verilator launcher: $safe_verilator" >&2
    exit 2
fi

case "$sim_cpu" in
    fx68k) ;;
    j68) ;;
    *) echo "Unsupported BUCKY_SIM_CPU=$sim_cpu (expected fx68k or j68)" >&2; exit 2 ;;
esac

# The upstream workbench wrapper predates the current core mem.yaml.  Keep it
# immutable and create a checked derived copy containing main.cache_size=8;
# a normal JTFRAME regeneration emits the same CACHE1_SIZE parameter.
generated_sdram="$root/.workbench/generated/jtbucky_game_sdram.v"
prepare_args=()
if [[ "$sim_skip_erase" == 1 ]]; then
    prepare_args+=( --skip-ram-erase )
fi
python "$root/cores/bucky/tools/prepare_bucky_sdram.py" \
    "${prepare_args[@]}" \
    "$jtroot/cores/bucky/mister/jtbucky_game_sdram.v" "$generated_sdram"

# The safe Verilator wrapper is a native Windows executable.  Convert all
# paths assembled by the MSYS shell before passing them to it; otherwise a
# `/d/...` path is treated as a literal filename on the Windows side.
native_path() {
    cygpath -w "$1"
}

qip_file="$jtroot/cores/bucky/files.qip"
if [[ ! -f "$qip_file" ]]; then
    qip_file="$jtroot/cores/bucky/mister/files.qip"
fi
if [[ ! -f "$qip_file" ]]; then
    echo "Missing Bucky files.qip under cores/bucky or cores/bucky/mister" >&2
    exit 2
fi

mapfile -t qip_sources < <(
    grep -E '(^| )((SYSTEM)?VERILOG)_FILE ' "$qip_file" |
    sed -E 's/.* (.*)$/\1/' |
    sed 's#\\#/#g' |
    while IFS= read -r path; do
        case "$path" in
            *.vhd|*.VHDL) continue ;;
            *"/cores/bucky/jtbucky_game_sdram.v"|*"/cores/bucky/mister/jtbucky_game_sdram.v") continue ;;
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
    "$(native_path "$root/cores/bucky/rtl/sim/bucky_contract_assertions.sv")"
    "$(native_path "$root/cores/bucky/hdl/sim/tb_bucky_parent.sv")"
    "$(native_path "$root/cores/bucky/hdl/sim/sim_headless.cpp")"
)
if [[ "$sim_savable" == 1 ]]; then
    sources+=("$(native_path "$root/cores/bucky/hdl/sim/sim_savable.cpp")")
fi
for source in "${qip_sources[@]}"; do
    sources+=("$(native_path "$source")")
done

defs=(
    -DSIMULATION -DJTFRAME_MEMGEN
    -DGAMETOP=jtbucky_game_sdram -DJTFRAME_SDRAM96 -DJTFRAME_CLK48 -DJTFRAME_NO_DB15 -DJTFRAME_MCLK=48000
    -DJTFRAME_DIALEMU_LEFT=0 -DJTFRAME_PXLCLK=8 -DJTFRAME_COLORW=8
    -DJTFRAME_BUTTONS=3 -DJTFRAME_WIDTH=384 -DJTFRAME_HEIGHT=224
    -DJTFRAME_STEREO -DJTFRAME_RELEASE -DJTFRAME_HEADER=16
    # Only the sprite bank consumes a four-beat line. The other generated
    # slots use their normal two-beat caches so sparse PCM/CPU traffic does
    # not occupy the shared SDRAM bank for unused return words.
    -DJTFRAME_BA3_LEN=64 -DJTFRAME_IOCTL_RD=128
    -DJTFRAME_TIMESTAMP=0 -DJTFRAME_LF_HW=1 -DJTFRAME_LF_VW=1
    -DJTFRAME_MR_FASTIO=0 -DSND_RAMW=13
    # Some JTFRAME generated debug sources are parsed even in release builds;
    # provide their harmless geometry default so Verilator can elaborate the
    # same source closure Quartus accepts.
    -DJTFRAME_DEBUG_VPOS=0
)

# Keep the default model strict for differential acceptance.  A separate
# exploratory binary may opt into Verilator's throughput flags when a long
# visual replay is needed; that binary is never evidence of exactness.
if [[ "$sim_fast" == 1 ]]; then
    defs+=( --x-assign fast --x-initial fast --noassert -DBUCKY_FAST_SIM )
else
    # Pin correctness semantics instead of relying on version-dependent
    # defaults.  The project-owned event probes provide the cold replay
    # evidence; optional waveform support is built only by a dedicated narrow
    # trace variant whose host dependencies have been verified.
    defs+=( --assert --x-assign unique --x-initial unique --MMD -Wall )
fi
# Match the production core by default: without JTFRAME_J68, jtframe_m68k
# instantiates fx68k.  J68 is useful for targeted diagnostics but must not be
# the acceptance CPU because an implementation-specific exception can be
# mistaken for a GX173/core bus defect.
case "$sim_cpu" in
    fx68k) ;;
    j68) defs+=( -DJTFRAME_J68 ) ;;
esac
if [[ "$sim_savable" == 1 ]]; then
    defs+=( -DBUCKY_EXTERNAL_CLOCK )
fi

includes=(
    "-I$(native_path "$root/.workbench/upstream/jtcores/modules/jtframe/hdl/inc")"
    "-I$(native_path "$root/.workbench/upstream/jtcores/cores/bucky/mister")"
    "-I$(native_path "$root/cores/bucky/hdl")"
    "-I$(native_path "$root/.workbench/upstream/jtcores/modules/jtframe/hdl/cpu/t80")"
    "-I$(native_path 'C:/Users/meath/AppData/Local/Temp/bucky-j68-elab')"
)

# Verilator appends its default -Os after user CFLAGS.  Repeat -O3 last so
# the generated model keeps native optimizer speed during long replays.
sim_cflags='-O3 -march=native -D_GLIBCXX_USE_CXX11_ABI=0 -O3'
sim_ldflags=''
if [[ "$sim_lto" == 1 ]]; then
    sim_cflags+=' -flto'
    sim_ldflags+=' -flto'
fi
common_args=(
    --threads 1 -O3 -Wno-fatal
    --top-module tb_bucky_parent --Mdir "$(native_path "$mdir")" --build -j "$build_jobs"
    --output-split "$sim_output_split"
    -CFLAGS "$sim_cflags"
    -LDFLAGS "$sim_ldflags"
)
if [[ "$sim_savable" == 1 ]]; then
    # Externally driven clocks remove the event scheduler and make complete
    # VerilatedSave checkpoints legal.  Assertions and strict X behavior stay
    # enabled; this is a correctness model, not the exploratory fast variant.
    "$safe_verilator" --cc --exe --savable \
        "${common_args[@]}" "${defs[@]}" "${includes[@]}" "${sources[@]}"
else
    "$safe_verilator" --binary --timing \
        "${common_args[@]}" "${defs[@]}" "${includes[@]}" "${sources[@]}"
fi
