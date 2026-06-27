#!/bin/bash
# Run all Verilog testbenches
set -e
echo "=== Running Verilog Testbenches ==="
for tb in hardware/tb/tb_*.v; do
    module=$(basename $tb .v | sed 's/tb_//')
    rtl_file="hardware/rtl/${module}.v"
    out="sim/${module}_sim"
    echo "--- Simulating $module ---"
    if [ -f "$rtl_file" ]; then
        # -g2012: SystemVerilog mode (array ports, '0 literals, etc.)
        iverilog -g2012 -o $out $tb $rtl_file && vvp $out
    else
        echo "RTL not yet written: $rtl_file"
    fi
done
