# Running OpenROAD Place & Route

## Prerequisites
- OpenROAD installed (see: https://openroad.readthedocs.io)
- Sky130 PDK installed via volare:
    pip install volare
    volare enable --pdk sky130 <latest_hash>

## Steps
1. Set environment:
    export PDK_ROOT=/path/to/pdk
    export PLATFORM=sky130hs

2. Copy your netlist:
    cp physical/synth/snn_top_mapped.v OpenROAD-flow-scripts/flow/designs/src/snn_top/

3. Write config.mk (provided in physical/openroad/config.mk)

4. Run the flow:
    cd OpenROAD-flow-scripts
    make DESIGN_CONFIG=../mini-loihi/physical/openroad/config.mk

5. View GDSII:
    klayout results/final/gds/snn_top.gds

## Expected Runtime: 10-30 minutes on a modern laptop

---

## Note on the mapped netlist

`physical/synth/synth.ys` writes a **generic** gate netlist
(`snn_top_synth.v`). To produce the Sky130-mapped netlist
(`snn_top_mapped.v`) that OpenROAD expects, uncomment the technology-mapping
lines at the bottom of `synth.ys` and point them at your Sky130 liberty file,
e.g.:

```tcl
dfflibmap -liberty $PDK_ROOT/sky130A/.../sky130_fd_sc_hd__tt_025C_1v80.lib
abc       -liberty $PDK_ROOT/sky130A/.../sky130_fd_sc_hd__tt_025C_1v80.lib
write_verilog physical/synth/snn_top_mapped.v
```

A minimal timing constraint is provided in
`physical/openroad/constraint.sdc` (10 ns / 100 MHz clock); adjust to taste.
