// Phase 3 — Integration: snn_top
// Top-level module wiring all five RTL modules into the full 8->4->2 datapath,
// orchestrated by timestep_ctrl. Mirrors the complete forward inference of the
// trained snnTorch model.
//
// TODO: instantiate and connect timestep_ctrl, weight_rom, synapse_acc,
//       lif_core, and spike_router for both layers.

`default_nettype none

module snn_top ();

endmodule

`default_nettype wire
