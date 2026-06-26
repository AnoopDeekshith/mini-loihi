// Phase 2 — Module 4: lif_core
// Hardware equivalent of snn.Leaky(beta=beta) forward pass.
// Implements Leaky Integrate-and-Fire dynamics per timestep in Q8.8:
//   V[t] = beta * V[t-1] + I_syn[t]
//   if V[t] >= theta: spike_out = 1, V[t] = 0
//   else:             spike_out = 0
//
// TODO: implement membrane update, threshold compare, and reset.

`default_nettype none

module lif_core ();

endmodule

`default_nettype wire
