# Mini Loihi — Project Status

A miniature Loihi-style spiking neural network processor taken from a trained
snnTorch model all the way to a synthesized gate-level netlist, ready for
Sky130 place & route.

## Phase Status

| Phase | Description | Status |
|-------|-------------|--------|
| 0 | Environment, LIF demo, DFF warmup | ✅ |
| 1 | snnTorch training, Q8.8 weight export | ✅ |
| 2 | 5 RTL modules with testbenches | ✅ |
| 3 | Integration testbench, system simulation | ✅ |
| 4 | Yosys synthesis complete, OpenROAD ready for manual run | 🔄 |

## Pipeline at a Glance

```
Iris (2 classes)
   │  rate-code (20 steps, Bernoulli)
   ▼
snnTorch 8→4→2 LIF  ──train──►  100% train / 100% test accuracy
   │  quantize Q8.8 (cos sim 0.99999, 0% accuracy loss)
   ▼
hex weights ──►  5 Verilog RTL modules ──►  snn_top integration
   │  iverilog: all unit + integration testbenches PASS
   ▼
Yosys synthesis  ──►  gate-level netlist  ──►  OpenROAD / Sky130 (manual)
```

## Verification Summary

- **Software**: float vs Q8.8 quantized models agree 20/20 on the test set.
- **Hardware unit tests**: `dff`, `timestep_ctrl`, `weight_rom`, `synapse_acc`,
  `lif_core`, `spike_router` — all PASS.
- **Integration** (`tb_snn_top`): setosa → class 0 (`[3, 0]`),
  versicolor → class 1 (`[0, 4]`) — both classified correctly.

## Code Size

| Category | Lines |
|----------|------:|
| Python (training + export) | 647 |
| Verilog RTL (`hardware/rtl/`) | 649 |
| Verilog testbenches (`hardware/tb/`) | 786 |
| **Total Verilog** | **1435** |

## Synthesis Results (Yosys 0.63)

Top module `snn_top`, generic gate mapping, fully flattened:

| Metric | Value |
|--------|------:|
| Cells (total) | 4810 |
| Flip-flops (DFF/DFFE/SDFF) | ~304 |
| Wires | 4578 |
| Top-level ports | 6 |

Dominant cell types: `$_XOR_` / `$_XNOR_` (~1143) and `$_ANDNOT_`/`$_AND_`
(~1876) — driven mainly by the four 16×16 Q8.8 multipliers in the two LIF
layers. No synthesis warnings or errors.

Netlist: [`physical/synth/snn_top_synth.v`](../physical/synth/snn_top_synth.v).
Regenerate the full synthesis report with:
`yosys physical/synth/synth.ys | tee physical/synth/synth.log` (the log is
git-ignored).

## Remaining for Phase 4 (manual)

1. Map to Sky130 cells (uncomment `dfflibmap` / `abc -liberty` in `synth.ys`).
2. Run OpenROAD place & route — see
   [`physical/openroad/README_OPENROAD.md`](../physical/openroad/README_OPENROAD.md).
3. Produce and inspect GDSII in KLayout.
