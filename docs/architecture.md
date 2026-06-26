# Architecture — snnTorch ↔ Verilog Mapping

This document describes how each Verilog RTL module maps to a corresponding
concept in the snnTorch (PyTorch) software model. The hardware is a direct,
cycle-accurate realization of the trained spiking neural network: an 8→4→2 LIF
network using Q8.8 fixed-point arithmetic.

## Module ↔ snnTorch Mapping

### `timestep_ctrl` ↔ the `for` loop over time steps in snnTorch
In snnTorch, inference unrolls the network over discrete time steps:

```python
for step in range(num_steps):
    ...
```

`timestep_ctrl` is the hardware finite-state machine that drives this loop. It
generates the timestep counter, sequences the per-step phases (load weights →
accumulate synapses → update membrane → emit spikes), and signals when all
timesteps for an inference are complete.

### `weight_rom` ↔ `nn.Linear` weight matrix
Each `nn.Linear` layer holds a learned weight matrix `W`. After training, those
weights are quantized to Q8.8 and frozen. `weight_rom` is the read-only memory
that stores these quantized weights (loaded from `layer1_weights.hex` /
`layer2_weights.hex`) and serves the correct weight for a given
(neuron, synapse) address requested by the accumulator.

### `synapse_acc` ↔ `linear(x)` — weighted sum of inputs
The forward pass of `nn.Linear` computes `y = W·x + b`, a weighted sum of inputs.
`synapse_acc` performs this multiply-accumulate in hardware: for each output
neuron it multiplies incoming spikes by their Q8.8 weights (fetched from
`weight_rom`) and accumulates the synaptic current `I_syn` for that timestep.

### `lif_core` ↔ `snn.Leaky(beta=β)` forward pass
`snn.Leaky` implements Leaky Integrate-and-Fire dynamics. `lif_core` is the
hardware equivalent of its forward pass, computing per timestep:

```
V[t] = β × V[t-1] + I_syn[t]
if V[t] ≥ θ: spike_out = 1, V[t] = 0
else:        spike_out = 0
```

with β (leak factor) and θ (threshold) taken from training and applied in Q8.8.

### `spike_router` ↔ the layer-to-layer data flow
In snnTorch, the output spikes of one `snn.Leaky` layer become the input to the
next layer. `spike_router` implements this connectivity in hardware: it collects
the spike vector emitted by layer 1's `lif_core` neurons and routes it as the
input spike stream feeding layer 2's `synapse_acc`, handling the fan-out between
layers.

## Top-Level Integration
`snn_top` instantiates and wires all five modules into the full 8→4→2 datapath,
orchestrated by `timestep_ctrl`, mirroring the complete forward inference of the
trained snnTorch model.
