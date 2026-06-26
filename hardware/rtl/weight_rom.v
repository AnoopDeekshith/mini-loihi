// Phase 2 — Module 2: weight_rom
// Hardware equivalent of an nn.Linear weight matrix.
// Read-only memory storing Q8.8 quantized weights loaded from the .hex files in
// hardware/mem/. Serves the weight for a requested (neuron, synapse) address.
//
// TODO: implement ROM with $readmemh initialization and addressed read.

`default_nettype none

module weight_rom ();

endmodule

`default_nettype wire
