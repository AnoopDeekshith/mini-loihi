# Mini Loihi — Neuromorphic SNN Processor
A miniature Loihi-style spiking neural network processor built from scratch.

## Architecture
- **Software**: snnTorch (PyTorch) trains an 8→4→2 LIF network on Iris dataset
- **Bridge**: Trained weights exported as Q8.8 fixed-point hex files
- **Hardware**: 5 Verilog RTL modules implement LIF neuron dynamics
- **Physical**: Yosys synthesis → OpenROAD place & route → Sky130 GDSII

## Phases
| Phase | Goal | Status |
|-------|------|--------|
| 0 | Environment setup + first spike | 🔲 |
| 1 | Train SNN + export weights | ✅ |
| 2 | RTL — 5 Verilog modules | 🔲 |
| 3 | Integration testbench | 🔲 |
| 4 | Physical implementation | 🔲 |

## Neuron Model
LIF dynamics (per timestep):
  V[t] = β × V[t-1] + I_syn[t]
  if V[t] ≥ θ: spike_out = 1, V[t] = 0
  else:         spike_out = 0

Where β (leak factor) and θ (threshold) come from snnTorch training.

## Fixed-Point Format
All hardware arithmetic uses Q8.8 (16-bit, 8 integer bits, 8 fractional bits).

## Tools
- Python 3.10+, snnTorch, PyTorch
- Verilog simulation: EDA Playground (browser) or Icarus Verilog
- Synthesis: Yosys + ABC
- Place & Route: OpenROAD
- PDK: SkyWater Sky130
