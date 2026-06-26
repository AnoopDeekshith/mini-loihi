#!/usr/bin/env bash
# Run all mini-loihi testbenches with Icarus Verilog.
#
# Usage: ./sim/run_sim.sh
#
# Requires: iverilog + vvp (Icarus Verilog) on PATH.

set -euo pipefail

RTL_DIR="hardware/rtl"
TB_DIR="hardware/tb"
WORK_DIR="work"

mkdir -p "$WORK_DIR"

# Each testbench is paired with its DUT. snn_top pulls in all RTL modules.
declare -a TESTS=(
    "tb_timestep_ctrl:${RTL_DIR}/timestep_ctrl.v"
    "tb_weight_rom:${RTL_DIR}/weight_rom.v"
    "tb_synapse_acc:${RTL_DIR}/synapse_acc.v"
    "tb_lif_core:${RTL_DIR}/lif_core.v"
    "tb_spike_router:${RTL_DIR}/spike_router.v"
    "tb_snn_top:${RTL_DIR}/timestep_ctrl.v ${RTL_DIR}/weight_rom.v ${RTL_DIR}/synapse_acc.v ${RTL_DIR}/lif_core.v ${RTL_DIR}/spike_router.v ${RTL_DIR}/snn_top.v"
)

for entry in "${TESTS[@]}"; do
    tb="${entry%%:*}"
    rtl="${entry#*:}"
    out="${WORK_DIR}/${tb}.vvp"

    echo "=== Compiling ${tb} ==="
    iverilog -g2012 -o "$out" "${TB_DIR}/${tb}.v" ${rtl}

    echo "=== Running ${tb} ==="
    vvp "$out"
    echo
done

echo "All testbenches complete."
