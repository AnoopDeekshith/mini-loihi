#!/bin/bash
# Run all Verilog testbenches (Icarus Verilog, SystemVerilog mode).
set -e
echo "=== Running Verilog Testbenches ==="

RTL=hardware/rtl
TB=hardware/tb

# run <name> <source files...> : compile + simulate one testbench.
run() {
    local name=$1; shift
    echo "--- Simulating $name ---"
    # -g2012: SystemVerilog mode (array ports, '0 literals, etc.)
    iverilog -g2012 -o "sim/${name}_sim" "$@" && vvp "sim/${name}_sim"
}

# Unit testbenches (one DUT each).
run dff           "$TB/tb_dff.v"            "$RTL/dff.v"
run timestep_ctrl "$TB/tb_timestep_ctrl.v"  "$RTL/timestep_ctrl.v"
run weight_rom    "$TB/tb_weight_rom.v"     "$RTL/weight_rom.v"
run synapse_acc   "$TB/tb_synapse_acc.v"    "$RTL/synapse_acc.v"
run lif_core      "$TB/tb_lif_core.v"       "$RTL/lif_core.v"
run spike_router  "$TB/tb_spike_router.v"   "$RTL/spike_router.v"

# Full 8->4->2 integration (snn_top needs every module).
run snn_top "$TB/tb_snn_top.v" \
    "$RTL/snn_top.v" "$RTL/timestep_ctrl.v" "$RTL/weight_rom.v" \
    "$RTL/synapse_acc.v" "$RTL/lif_core.v" "$RTL/spike_router.v"

echo "=== All testbenches complete ==="
