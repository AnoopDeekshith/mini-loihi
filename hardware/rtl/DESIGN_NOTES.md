# Mini Loihi — RTL Design Notes

Implementation notes for the 8→4→2 spiking neural network processor. All
arithmetic is Q8.8 fixed-point (16-bit signed: 8 integer bits, 8 fractional).

## Why `synapse_acc` is serial (area vs. speed tradeoff)

`synapse_acc` walks the (pre, post) weight pairs **one per clock cycle** rather
than computing all post-neuron currents in parallel. For an N_PRE×N_POST layer
this takes ~N_PRE·N_POST cycles per timestep (≈36 for layer 1's 8×4).

The tradeoff:

- **Serial (chosen):** one multiplier-free adder and one weight-ROM read port.
  Area scales with N_POST accumulators only; the weight memory is read
  sequentially. Cheap in silicon, slow in cycles. This matches a neuromorphic
  design point — event-driven, low area, clock cycles are plentiful relative to
  the biological timestep.
- **Parallel:** N_PRE·N_POST multiply-accumulate lanes finishing in ~1 cycle,
  but N_POST read ports (or a fully unrolled weight bank) and far more area.

Because spikes are 1-bit, each "multiply" is just a conditional add of the
weight when `spike_in[pre]` is set — no real multiplier is needed in this block.

The accumulator carries `DATA_W + clog2(N_PRE)` bits (19 for layer 1) so the sum
of up to N_PRE signed weights cannot overflow.

### Pipeline / latency

The address→weight path has **two register stages** (synapse_acc's registered
address output + weight_rom's registered data output), so `synapse_acc` keeps a
2-deep metadata pipeline (`s1`, `s2`) to align each (post, spike) pair with its
weight when it arrives. This sustains one accumulate per clock; `acc_done`
asserts a few cycles after the last pair drains.

## How fixed-point Q8.8 multiply works in `lif_core`

The only true multiply in the datapath is the membrane leak `V_mem * beta`:

```
prod   = V_mem * beta;                 // Q8.8 * Q8.8 = Q16.16 (32-bit)
V_leak = prod[23:8];                    // >> 8 re-normalizes back to Q8.8
V_new  = V_leak + I_syn;                // Q8.8 add (guard bit prevents overflow)
```

Multiplying two Q8.8 numbers yields a Q16.16 product (16 fractional bits). To
return to Q8.8 we shift right by `FRAC_BITS = 8`, i.e. keep bits `[23:8]` of the
32-bit product. With `beta = 0x00E6` (≈0.9) and the membrane reset on firing,
`V_mem` stays small and positive, so the truncated window never overflows.

**Signedness gotcha (fixed):** `I_syn` and weights can be negative. A Verilog
**concatenation is unsigned**, so comparing `V_new >= {theta[15], theta}`
silently promoted a negative `V_new` to a huge unsigned value and fired the
neuron. The threshold compare is therefore wrapped in `$signed(...)` on both
sides. (This bug was invisible to the unit test, which only drove positive
currents — it was caught by the full integration against a Python Q8.8
reference.)

## What `spike_router` would look like in a larger design (mesh NoC)

Here `spike_router` is a registered pass-through: it latches one layer's spike
vector and pulses `route_valid` for the next layer. That is all an 8→4→2 chain
needs.

In a real Loihi-scale device the router becomes a **mesh network-on-chip**:

- Neuron cores sit at the nodes of a 2-D mesh; spikes become **packets**
  (source core, axon/neuron id, optionally a timestamp).
- A **routing table** per core maps each firing neuron to one or more
  destination cores/axons (multicast fan-out).
- Packets are forwarded hop-by-hop (e.g. dimension-order X-Y routing) with
  input buffering and back-pressure/flow control.
- This decouples connectivity from physical adjacency, so arbitrary
  layer-to-layer (and recurrent) topologies are possible without dedicated
  wires per synapse.

`spike_router` is the seam where that table/NoC would be dropped in.

## Top-level control (`snn_top`)

One timestep of compute here spans many cycles (serial `synapse_acc`), so
`snn_top` runs a **master FSM** that sequences each timestep's datapath via the
modules' `acc_done` / `route_valid` handshakes:

```
S_START -> S_L1_WAIT -> S_ROUTE -> S_ROUTE_WAIT -> S_L2_WAIT
        -> S_LIF2_WAIT -> S_COUNT -> S_CHECK -> S_DECIDE -> (loop / S_FINISH)
```

`S_START` latches the timestep's input spikes and kicks off layer 1; each
`*_WAIT` state blocks on a module's done/valid handshake; `S_COUNT` accumulates
the output spikes and pulses `adv`.

`timestep_ctrl` runs on the **main clock** with `adv` as a **clock-enable** (one
pulse per completed timestep) — no gated/derived clock. Because `adv` and the
counter share the main clock, `S_CHECK` lets the counter advance and `S_DECIDE`
reads the now-stable `tc_done` one cycle later (avoiding a same-edge race). This
makes `timestep_ctrl` genuinely count *completed* timesteps and produce `done`.

LIF `spike_out` and `V_mem` are **held** between updates (they only change on
`acc_done`), which keeps downstream capture timing simple — the membrane state
persists across timesteps exactly like snnTorch's stateful `Leaky` neuron.

## Known limitations

1. **`spike_count` width.** Declared 8-bit per output neuron (the spec's 2-bit
   field cannot hold ~20-step counts). Argmax of the two counters gives the
   class.
2. **Accumulator narrowing.** `synapse_acc`'s 18/19-bit `I_syn` is truncated to
   16-bit for `lif_core`. Safe here because |sum of ≤8 weights with |w|<1| stays
   well inside 16-bit range; a larger network should saturate instead.
3. **Fixed `beta`/`theta`.** Hardwired to 0x00E6 / 0x0100 in `snn_top` rather
   than loaded from `neuron_cfg.hex` (the file is exported but not yet consumed
   by the RTL).
4. **No bias.** The trained network is bias-free, matching `nn.Linear(bias=False)`.
5. **Throughput.** ~55 cycles/timestep, ~20 timesteps per inference. Optimized
   for area and clarity, not latency.
