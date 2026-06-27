// Phase 2A — Module 3: synapse_acc
// Serial synaptic accumulator — the hardware equivalent of linear(x), the
// weighted sum of input spikes. On `tick` it walks all (pre, post) pairs one
// per clock (row-major addr = pre*N_POST + post), driving the weight ROM and
// accumulating weight[pre][post] into I_syn[post] whenever spike_in[pre] is set.
//
// The address->weight path has two register stages of latency (this module's
// registered address output + the weight_rom's registered data output), so a
// 2-deep metadata pipeline (s1, s2) keeps each post-index/spike aligned with
// the weight when it finally arrives. FSM: IDLE -> ACCUMULATE -> DONE.

`default_nettype none

module synapse_acc #(
    parameter N_PRE  = 8,
    parameter N_POST = 4,
    parameter DATA_W = 16,                     // Q8.8
    // Derived widths (do not override): exposed here so they are visible to the
    // port declarations below.
    parameter PRE_AW  = $clog2(N_PRE),         // 3
    parameter POST_AW = $clog2(N_POST),        // 2
    parameter ACC_W   = DATA_W + $clog2(N_PRE) // 19
) (
    input  wire                clk,
    input  wire                rst_n,
    input  wire                tick,           // from timestep_ctrl
    input  wire [N_PRE-1:0]    spike_in,       // 1 spike bit per presynaptic neuron
    input  wire [DATA_W-1:0]   weight_data,    // from weight_rom (one weight/cycle)
    output reg  [PRE_AW-1:0]      weight_addr_pre,
    output reg  [POST_AW-1:0]     weight_addr_post,
    // I_syn is a flattened packed vector of N_POST accumulators (ACC_W each),
    // post-neuron k occupying bits [k*ACC_W +: ACC_W]. Flattened (rather than an
    // unpacked array port) so the design is synthesizable by Yosys.
    output reg  [N_POST*ACC_W-1:0] I_syn,
    output reg                    acc_done     // 1-cycle pulse: I_syn valid
);

    localparam NPAIRS  = N_PRE * N_POST;           // 32
    localparam CW      = $clog2(NPAIRS + 1);       // index counter width

    localparam [1:0] IDLE = 2'd0, ACCUMULATE = 2'd1, DONE = 2'd2;

    reg [1:0]  state;
    reg [CW-1:0] cnt;          // current pair index being issued (0..NPAIRS)

    // 2-deep metadata pipeline (aligns post/spike with the arriving weight).
    reg                s1_valid, s2_valid;
    reg [POST_AW-1:0]  s1_post,  s2_post;
    reg                s1_spike, s2_spike;

    // Decode the current index into (pre, post): addr = pre*N_POST + post.
    wire [PRE_AW-1:0]  pre_idx  = cnt[POST_AW + PRE_AW - 1 : POST_AW];
    wire [POST_AW-1:0] post_idx = cnt[POST_AW-1:0];

    // Sign-extend the incoming Q8.8 weight to the accumulator width.
    wire signed [ACC_W-1:0] w_ext =
        {{(ACC_W-DATA_W){weight_data[DATA_W-1]}}, weight_data};

    integer j;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state            <= IDLE;
            cnt              <= {CW{1'b0}};
            acc_done         <= 1'b0;
            weight_addr_pre  <= {PRE_AW{1'b0}};
            weight_addr_post <= {POST_AW{1'b0}};
            s1_valid <= 1'b0; s2_valid <= 1'b0;
            s1_spike <= 1'b0; s2_spike <= 1'b0;
            s1_post  <= {POST_AW{1'b0}}; s2_post <= {POST_AW{1'b0}};
            for (j = 0; j < N_POST; j = j + 1)
                I_syn[j*ACC_W +: ACC_W] <= {ACC_W{1'b0}};
        end else begin
            acc_done <= 1'b0;   // default: pulse

            case (state)
                IDLE: begin
                    if (tick) begin
                        for (j = 0; j < N_POST; j = j + 1)
                            I_syn[j*ACC_W +: ACC_W] <= {ACC_W{1'b0}};
                        cnt      <= {CW{1'b0}};
                        s1_valid <= 1'b0;
                        s2_valid <= 1'b0;
                        state    <= ACCUMULATE;
                    end
                end

                ACCUMULATE: begin
                    // (1) Accumulate the weight that has now arrived (matches s2).
                    if (s2_valid && s2_spike)
                        I_syn[s2_post*ACC_W +: ACC_W] <=
                            I_syn[s2_post*ACC_W +: ACC_W] + w_ext;

                    // (2) Shift the metadata pipeline s1 -> s2.
                    s2_valid <= s1_valid;
                    s2_post  <= s1_post;
                    s2_spike <= s1_spike;

                    // (3) Issue the address for the current pair, or drain.
                    if (cnt < NPAIRS) begin
                        weight_addr_pre  <= pre_idx;
                        weight_addr_post <= post_idx;
                        s1_valid <= 1'b1;
                        s1_post  <= post_idx;
                        s1_spike <= spike_in[pre_idx];
                        cnt      <= cnt + 1'b1;
                    end else begin
                        // All addresses issued; flush the pipeline.
                        s1_valid <= 1'b0;
                        if (!s1_valid && !s2_valid) begin
                            acc_done <= 1'b1;
                            state    <= DONE;
                        end
                    end
                end

                DONE: begin
                    state <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule

`default_nettype wire
