// Phase 3 — Top level: snn_top
// The complete 8->4->2 spiking neural network processor. A master FSM sequences
// one timestep's full datapath each iteration:
//
//   latch input spikes -> synapse_acc_l1 -> lif_core_l1 -> spike_router
//                      -> synapse_acc_l2 -> lif_core_l2 -> accumulate spikes
//
// then advances timestep_ctrl. After n_steps timesteps `done` asserts and the
// per-output-neuron spike counts are valid; argmax(spike_count) is the class.
//
// NOTE on control: the spec's timestep_ctrl is a free-running per-cycle counter,
// but each timestep here takes many cycles (synapse_acc is serial, ~36 cycles).
// So the FSM drives the heavy modules via their done/valid handshakes and uses
// `adv` (one pulse per completed timestep) as timestep_ctrl's clock, so
// timestep_ctrl genuinely counts *completed* timesteps and produces `done`.
// (This makes `adv` a derived clock — fine for this project; see DESIGN_NOTES.)

`default_nettype none

module snn_top (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [7:0]  spike_in_bus,     // 8 input neurons (1 bit each)
    input  wire [7:0]  n_steps,          // number of timesteps (e.g. 20)
    output reg  [7:0]  spike_count [0:1], // spike count per output neuron
    output reg         done              // high after n_steps complete
);

    // Q8.8 LIF dynamics (from training: beta=0.9, theta=1.0).
    localparam [15:0] BETA  = 16'h00E6;
    localparam [15:0] THETA = 16'h0100;

    // ---------------------------------------------------------------
    // Layer 1: synapse_acc (8->4) + weight_rom + lif_core (4 neurons)
    // ---------------------------------------------------------------
    localparam L1_ACC_W = 16 + 3;   // DATA_W + clog2(N_PRE=8) = 19

    reg  [7:0]        spike_in_l1;        // latched input spikes for the timestep
    reg               l1_tick;
    wire [2:0]        l1_addr_pre;
    wire [1:0]        l1_addr_post;
    wire [L1_ACC_W-1:0] isyn_l1 [0:3];
    wire              l1_acc_done;
    wire [15:0]       l1_weight_data;

    weight_rom #(
        .N_PRE(8), .N_POST(4), .DATA_W(16),
        .MEM_FILE("hardware/mem/layer1_weights.hex")
    ) wrom_l1 (
        .clk      (clk),
        .addr     ({l1_addr_pre, l1_addr_post}),   // row-major pre*4+post
        .data_out (l1_weight_data)
    );

    synapse_acc #(.N_PRE(8), .N_POST(4), .DATA_W(16)) sacc_l1 (
        .clk              (clk),
        .rst_n            (rst_n),
        .tick             (l1_tick),
        .spike_in         (spike_in_l1),
        .weight_data      (l1_weight_data),
        .weight_addr_pre  (l1_addr_pre),
        .weight_addr_post (l1_addr_post),
        .I_syn            (isyn_l1),
        .acc_done         (l1_acc_done)
    );

    // Narrow the 19-bit accumulator to 16-bit Q8.8 for the LIF (values are
    // small: |sum of <=8 weights with |w|<1| << 16-bit range).
    wire [15:0] isyn_l1_16 [0:3];
    wire [3:0]  spike_l1;
    wire [15:0] vmem_l1 [0:3];
    genvar i1;
    generate
        for (i1 = 0; i1 < 4; i1 = i1 + 1) begin : narrow_l1
            assign isyn_l1_16[i1] = isyn_l1[i1][15:0];
        end
    endgenerate

    lif_core #(.DATA_W(16), .N_NEURON(4)) lif_l1 (
        .clk       (clk),
        .rst_n     (rst_n),
        .acc_done  (l1_acc_done),
        .I_syn     (isyn_l1_16),
        .beta      (BETA),
        .theta     (THETA),
        .spike_out (spike_l1),
        .V_mem     (vmem_l1)
    );

    // ---------------------------------------------------------------
    // Between layers: spike_router (4 -> 4)
    // ---------------------------------------------------------------
    reg          route_tick;
    wire [3:0]   spike_routed;
    wire         route_valid;

    spike_router #(.N_IN(4), .N_OUT(4)) router (
        .clk         (clk),
        .rst_n       (rst_n),
        .tick        (route_tick),
        .spike_in    (spike_l1),
        .spike_out   (spike_routed),
        .route_valid (route_valid)
    );

    // ---------------------------------------------------------------
    // Layer 2: synapse_acc (4->2) + weight_rom + lif_core (2 neurons)
    // ---------------------------------------------------------------
    localparam L2_ACC_W = 16 + 2;   // DATA_W + clog2(N_PRE=4) = 18

    wire [1:0]        l2_addr_pre;
    wire [0:0]        l2_addr_post;
    wire [L2_ACC_W-1:0] isyn_l2 [0:1];
    wire              l2_acc_done;
    wire [15:0]       l2_weight_data;

    weight_rom #(
        .N_PRE(4), .N_POST(2), .DATA_W(16),
        .MEM_FILE("hardware/mem/layer2_weights.hex")
    ) wrom_l2 (
        .clk      (clk),
        .addr     ({l2_addr_pre, l2_addr_post}),   // row-major pre*2+post
        .data_out (l2_weight_data)
    );

    synapse_acc #(.N_PRE(4), .N_POST(2), .DATA_W(16)) sacc_l2 (
        .clk              (clk),
        .rst_n            (rst_n),
        .tick             (route_valid),            // start L2 when routing done
        .spike_in         (spike_routed),
        .weight_data      (l2_weight_data),
        .weight_addr_pre  (l2_addr_pre),
        .weight_addr_post (l2_addr_post),
        .I_syn            (isyn_l2),
        .acc_done         (l2_acc_done)
    );

    wire [15:0] isyn_l2_16 [0:1];
    wire [1:0]  spike_l2;
    wire [15:0] vmem_l2 [0:1];
    genvar i2;
    generate
        for (i2 = 0; i2 < 2; i2 = i2 + 1) begin : narrow_l2
            assign isyn_l2_16[i2] = isyn_l2[i2][15:0];
        end
    endgenerate

    lif_core #(.DATA_W(16), .N_NEURON(2)) lif_l2 (
        .clk       (clk),
        .rst_n     (rst_n),
        .acc_done  (l2_acc_done),
        .I_syn     (isyn_l2_16),
        .beta      (BETA),
        .theta     (THETA),
        .spike_out (spike_l2),
        .V_mem     (vmem_l2)
    );

    // ---------------------------------------------------------------
    // Timestep counter (clocked once per completed timestep via `adv`)
    // ---------------------------------------------------------------
    reg          adv;
    wire         tc_tick;
    wire         tc_done;
    wire [7:0]   tc_step;

    timestep_ctrl tc (
        .clk        (adv),
        .rst_n      (rst_n),
        .n_steps    (n_steps),
        .tick       (tc_tick),
        .done       (tc_done),
        .step_count (tc_step)
    );

    // ---------------------------------------------------------------
    // Master sequencing FSM
    // ---------------------------------------------------------------
    localparam [3:0]
        S_IDLE      = 4'd0,
        S_START     = 4'd1,
        S_L1_WAIT   = 4'd2,
        S_ROUTE     = 4'd3,
        S_ROUTE_WAIT= 4'd4,
        S_L2_WAIT   = 4'd5,
        S_LIF2_WAIT = 4'd6,
        S_COUNT     = 4'd7,
        S_CHECK     = 4'd8,
        S_FINISH    = 4'd9;

    reg [3:0] state;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state          <= S_IDLE;
            l1_tick        <= 1'b0;
            route_tick     <= 1'b0;
            adv            <= 1'b0;
            done           <= 1'b0;
            spike_in_l1    <= 8'd0;
            spike_count[0] <= 8'd0;
            spike_count[1] <= 8'd0;
        end else begin
            // Default deassert of one-cycle pulses.
            l1_tick    <= 1'b0;
            route_tick <= 1'b0;
            adv        <= 1'b0;

            case (state)
                S_IDLE: begin
                    state <= S_START;
                end

                // Latch this timestep's input spikes and kick off layer 1.
                S_START: begin
                    spike_in_l1 <= spike_in_bus;
                    l1_tick     <= 1'b1;
                    state       <= S_L1_WAIT;
                end

                // Wait for L1 accumulation; lif_l1 updates on l1_acc_done.
                S_L1_WAIT: begin
                    if (l1_acc_done)
                        state <= S_ROUTE;
                end

                // Route layer-1 spikes to layer 2.
                S_ROUTE: begin
                    route_tick <= 1'b1;
                    state      <= S_ROUTE_WAIT;
                end

                // route_valid starts L2 (sacc_l2.tick = route_valid).
                S_ROUTE_WAIT: begin
                    if (route_valid)
                        state <= S_L2_WAIT;
                end

                // Wait for L2 accumulation; lif_l2 updates on l2_acc_done.
                S_L2_WAIT: begin
                    if (l2_acc_done)
                        state <= S_LIF2_WAIT;
                end

                // lif_l2.spike_out now valid (held).
                S_LIF2_WAIT: begin
                    state <= S_COUNT;
                end

                // Accumulate output spikes, then advance the timestep counter.
                S_COUNT: begin
                    spike_count[0] <= spike_count[0] + {7'd0, spike_l2[0]};
                    spike_count[1] <= spike_count[1] + {7'd0, spike_l2[1]};
                    adv            <= 1'b1;        // one timestep complete
                    state          <= S_CHECK;
                end

                // timestep_ctrl has advanced; check for completion.
                S_CHECK: begin
                    if (tc_done) begin
                        done  <= 1'b1;
                        state <= S_FINISH;
                    end else begin
                        state <= S_START;
                    end
                end

                S_FINISH: begin
                    done  <= 1'b1;
                    state <= S_FINISH;            // latch done
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule

`default_nettype wire
