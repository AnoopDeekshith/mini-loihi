// Phase 2B — Module 5: spike_router
// Routes one layer's spike outputs to the next layer's spike inputs — the
// hardware equivalent of snnTorch's layer-to-layer data flow. For this small
// 8->4->2 design it is a registered pass-through: on `tick` it latches spike_in
// and pulses route_valid one cycle later (giving spike_in time to settle). In a
// larger Loihi-style design this is where a mesh routing table / NoC would live.

`default_nettype none

module spike_router #(
    parameter N_IN  = 4,    // spikes from layer 1 LIF outputs
    parameter N_OUT = 4     // spike bus to layer 2 synapse_acc
) (
    input  wire             clk,
    input  wire             rst_n,
    input  wire             tick,         // from timestep_ctrl / layer-1 done
    input  wire [N_IN-1:0]  spike_in,     // from lif_core layer 1
    output reg  [N_OUT-1:0] spike_out,    // to synapse_acc layer 2
    output reg              route_valid   // 1-cycle pulse: spike_out valid
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            spike_out   <= {N_OUT{1'b0}};
            route_valid <= 1'b0;
        end else begin
            route_valid <= tick;          // pulse one cycle after tick
            if (tick) begin
                // Registered copy (zero-extended if N_OUT > N_IN).
                spike_out <= {{(N_OUT-N_IN){1'b0}}, spike_in};
            end
        end
    end

endmodule

`default_nettype wire
