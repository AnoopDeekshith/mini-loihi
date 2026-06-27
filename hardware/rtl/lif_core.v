// Phase 2B — Module 4: lif_core
// Leaky Integrate-and-Fire layer — the hardware equivalent of snn.Leaky's
// forward pass. On each acc_done pulse every neuron updates in parallel:
//
//     V_leak = (V_mem * beta) >> 8     (Q8.8 fixed-point multiply, keep [23:8])
//     V_new  = V_leak + I_syn
//     if V_new >= theta : spike=1, V_mem=0     (fire + reset to zero)
//     elif V_new < 0    : spike=0, V_mem=0     (underflow clamp)
//     else              : spike=0, V_mem=V_new
//
// All arithmetic is signed Q8.8 (I_syn may be negative). spike_out and V_mem
// hold their values between updates (they only change on acc_done), which keeps
// downstream capture timing simple in the integrated design.

`default_nettype none

module lif_core #(
    parameter DATA_W   = 16,    // Q8.8
    parameter N_NEURON = 4
) (
    input  wire                clk,
    input  wire                rst_n,
    input  wire                       acc_done,          // I_syn valid this cycle
    // I_syn and V_mem are flattened packed vectors (neuron k at [k*DATA_W +:
    // DATA_W]) rather than unpacked array ports, so the design is synthesizable.
    input  wire [N_NEURON*DATA_W-1:0] I_syn,             // synaptic current/neuron
    input  wire [DATA_W-1:0]          beta,              // Q8.8 leak factor
    input  wire [DATA_W-1:0]          theta,             // Q8.8 firing threshold
    output reg  [N_NEURON-1:0]        spike_out,         // 1 spike bit per neuron
    output reg  [N_NEURON*DATA_W-1:0] V_mem              // membrane potential (debug)
);

    localparam FRAC_BITS = 8;

    integer i;

    // Per-neuron combinational temporaries (blocking) reused each iteration.
    reg signed [DATA_W-1:0]   vm, isyn_i, bta_s, th_s, v_leak;
    reg signed [2*DATA_W-1:0] prod;
    reg signed [DATA_W:0]     v_new;

    // All N_NEURON neurons update in parallel on the same clock edge (the loop
    // body has no inter-neuron dependence). A single always block avoids driving
    // bits of spike_out from multiple processes.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            spike_out <= {N_NEURON{1'b0}};
            for (i = 0; i < N_NEURON; i = i + 1)
                V_mem[i*DATA_W +: DATA_W] <= {DATA_W{1'b0}};
        end else if (acc_done) begin
            bta_s = beta;
            th_s  = theta;
            for (i = 0; i < N_NEURON; i = i + 1) begin
                vm     = V_mem[i*DATA_W +: DATA_W];
                isyn_i = I_syn[i*DATA_W +: DATA_W];
                // Q8.8 multiply: keep bits [DATA_W+FRAC_BITS-1 : FRAC_BITS].
                prod   = vm * bta_s;
                v_leak = prod[DATA_W+FRAC_BITS-1 -: DATA_W];
                // Integrate with a guard bit against overflow.
                v_new  = {v_leak[DATA_W-1], v_leak} + {isyn_i[DATA_W-1], isyn_i};

                // $signed() forces a signed compare: a concatenation is
                // unsigned, which would wrongly promote a negative v_new.
                if ($signed(v_new) >= $signed({th_s[DATA_W-1], th_s})) begin
                    spike_out[i]              <= 1'b1;             // fire
                    V_mem[i*DATA_W +: DATA_W] <= {DATA_W{1'b0}};   // reset
                end else if (v_new < 0) begin
                    spike_out[i]              <= 1'b0;
                    V_mem[i*DATA_W +: DATA_W] <= {DATA_W{1'b0}};   // underflow clamp
                end else begin
                    spike_out[i]              <= 1'b0;
                    V_mem[i*DATA_W +: DATA_W] <= v_new[DATA_W-1:0];
                end
            end
        end
        // else: hold spike_out and V_mem between timesteps.
    end

endmodule

`default_nettype wire
