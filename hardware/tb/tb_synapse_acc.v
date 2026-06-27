// Testbench for synapse_acc (Phase 2A).
// Models a *registered* weight ROM (matching weight_rom's 1-cycle latency) so
// the address->weight path mirrors real hardware. Drives spikes at presynaptic
// neurons 0, 2, 5 and checks that, for every postsynaptic neuron j:
//     I_syn[j] == W[0][j] + W[2][j] + W[5][j]
// computed independently here in a wide signed accumulator. Also checks that
// acc_done pulses once, after at least N_PRE*N_POST accumulation cycles.

`timescale 1ns/1ps
`default_nettype none

module tb_synapse_acc ();

    localparam N_PRE   = 8;
    localparam N_POST  = 4;
    localparam DATA_W  = 16;
    localparam PRE_AW  = $clog2(N_PRE);            // 3
    localparam POST_AW = $clog2(N_POST);           // 2
    localparam ACC_W   = DATA_W + $clog2(N_PRE);   // 19
    localparam NPAIRS  = N_PRE * N_POST;           // 32

    reg                clk;
    reg                rst_n;
    reg                tick;
    reg  [N_PRE-1:0]   spike_in;

    wire [PRE_AW-1:0]  weight_addr_pre;
    wire [POST_AW-1:0] weight_addr_post;
    wire               acc_done;
    wire [ACC_W-1:0]   I_syn [0:N_POST-1];

    // --- Hardcoded weight ROM (registered, 1-cycle latency) ---
    reg  signed [DATA_W-1:0] W [0:NPAIRS-1];
    reg         [DATA_W-1:0] rom_q;
    wire [PRE_AW+POST_AW-1:0] rom_addr = {weight_addr_pre, weight_addr_post};

    integer k;
    initial begin
        // Distinct values spanning negative and positive (raw Q8.8 ints).
        for (k = 0; k < NPAIRS; k = k + 1)
            W[k] = k * 7 - 50;    // a=0 -> -50 ... a=31 -> 167
    end

    always @(posedge clk)
        rom_q <= W[rom_addr];

    // --- DUT ---
    synapse_acc #(
        .N_PRE  (N_PRE),
        .N_POST (N_POST),
        .DATA_W (DATA_W)
    ) dut (
        .clk              (clk),
        .rst_n            (rst_n),
        .tick             (tick),
        .spike_in         (spike_in),
        .weight_data      (rom_q),
        .weight_addr_pre  (weight_addr_pre),
        .weight_addr_post (weight_addr_post),
        .I_syn            (I_syn),
        .acc_done         (acc_done)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    // Count cycles from tick to acc_done.
    integer cyc = 0;
    integer cyc_at_done = -1;
    reg counting = 1'b0;
    always @(posedge clk) begin
        if (counting) cyc = cyc + 1;
    end

    integer j;
    integer errors = 0;
    reg signed [ACC_W-1:0] expected [0:N_POST-1];

    // Independent golden model: sum spiking presynaptic weights per post neuron.
    task compute_expected;
        integer pre, post;
        begin
            for (post = 0; post < N_POST; post = post + 1) begin
                expected[post] = 0;
                for (pre = 0; pre < N_PRE; pre = pre + 1) begin
                    if (spike_in[pre])
                        expected[post] = expected[post] + W[pre*N_POST + post];
                end
            end
        end
    endtask

    initial begin
        rst_n    = 1'b0;
        tick     = 1'b0;
        spike_in = '0;

        repeat (2) @(negedge clk);
        rst_n = 1'b1;

        // Spikes at presynaptic neurons 0, 2, 5.
        spike_in = 8'b0010_0101;   // bits 0,2,5
        compute_expected;

        // One-cycle tick pulse.
        @(negedge clk);
        tick     = 1'b1;
        counting = 1'b1;
        @(negedge clk);
        tick = 1'b0;

        // Wait for accumulation to complete.
        wait (acc_done == 1'b1);
        cyc_at_done = cyc;
        @(negedge clk);   // let final I_syn settle

        $display("acc_done asserted %0d cycles after tick (N_PRE*N_POST=%0d)",
                 cyc_at_done, NPAIRS);
        if (cyc_at_done >= NPAIRS)
            $display("PASS: acc_done after >= N_PRE*N_POST cycles");
        else begin
            $display("FAIL: acc_done too early (%0d < %0d)",
                     cyc_at_done, NPAIRS);
            errors = errors + 1;
        end

        for (j = 0; j < N_POST; j = j + 1) begin
            if ($signed(I_syn[j]) === expected[j])
                $display("PASS: I_syn[%0d] = %0d", j, $signed(I_syn[j]));
            else begin
                $display("FAIL: I_syn[%0d] = %0d, expected %0d",
                         j, $signed(I_syn[j]), expected[j]);
                errors = errors + 1;
            end
        end

        if (errors == 0)
            $display("ALL TESTS PASSED (tb_synapse_acc)");
        else
            $display("%0d TEST(S) FAILED (tb_synapse_acc)", errors);
        $finish;
    end

    // Safety timeout.
    initial begin
        #5000;
        $display("FAIL: timeout — acc_done never fired");
        $finish;
    end

endmodule

`default_nettype wire
