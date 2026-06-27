// Testbench for lif_core (Phase 2B).
// Drives a single LIF "timestep" per acc_done pulse and prints the membrane
// potential and spike for each step. Q8.8: beta=0x00E6 (~0.9), theta=0x0100 (1.0).
//   Test 1: I_syn = 0.5 (0x0080) for 5 steps -> must fire at least once.
//   Test 2: I_syn = 0.0            for 5 steps -> must never fire.
//   Test 3: I_syn = 1.5 (0x0180) once         -> must fire immediately.
// All 4 neurons are driven identically; neuron 0 is checked.

`timescale 1ns/1ps
`default_nettype none

module tb_lif_core ();

    localparam DATA_W = 16;
    localparam N      = 4;

    reg                clk;
    reg                rst_n;
    reg                acc_done;
    reg  [N*DATA_W-1:0] isyn;            // flattened: neuron k at [k*DATA_W +: DATA_W]
    reg  [DATA_W-1:0]  beta;
    reg  [DATA_W-1:0]  theta;
    wire [N-1:0]       spike_out;
    wire [N*DATA_W-1:0] V_mem;           // flattened

    integer errors = 0;
    reg     fired;
    integer n;

    lif_core #(.DATA_W(DATA_W), .N_NEURON(N)) dut (
        .clk       (clk),
        .rst_n     (rst_n),
        .acc_done  (acc_done),
        .I_syn     (isyn),
        .beta      (beta),
        .theta     (theta),
        .spike_out (spike_out),
        .V_mem     (V_mem)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    // One LIF timestep: present I_syn to all neurons, pulse acc_done, sample.
    task do_step;
        input [DATA_W-1:0] cur;
        begin
            for (n = 0; n < N; n = n + 1) isyn[n*DATA_W +: DATA_W] = cur;
            @(negedge clk); acc_done = 1'b1;
            @(posedge clk);                 // neuron updates here
            @(negedge clk); acc_done = 1'b0;
            $display("  I=0x%04h  V_mem[0]=0x%04h (%0d)  spike=%b",
                     cur, V_mem[0 +: DATA_W], $signed(V_mem[0 +: DATA_W]),
                     spike_out[0]);
            if (spike_out[0]) fired = 1'b1;
        end
    endtask

    task do_reset;
        begin
            rst_n = 1'b0;
            @(negedge clk);
            @(negedge clk);
            rst_n = 1'b1;
        end
    endtask

    initial begin
        beta     = 16'h00E6;   // ~0.9
        theta    = 16'h0100;   // 1.0
        acc_done = 1'b0;
        for (n = 0; n < N; n = n + 1) isyn[n*DATA_W +: DATA_W] = 16'h0000;

        do_reset;

        // --- Test 1: I_syn = 0.5 for 5 steps ---
        $display("Test 1: I_syn = 0.5 (0x0080) for 5 steps");
        fired = 1'b0;
        repeat (5) do_step(16'h0080);
        if (fired)
            $display("PASS: Test 1 neuron fired");
        else begin
            $display("FAIL: Test 1 neuron never fired");
            errors = errors + 1;
        end

        do_reset;

        // --- Test 2: I_syn = 0.0 -> never fires ---
        $display("Test 2: I_syn = 0.0 for 5 steps");
        fired = 1'b0;
        repeat (5) do_step(16'h0000);
        if (!fired)
            $display("PASS: Test 2 neuron never fired");
        else begin
            $display("FAIL: Test 2 neuron fired unexpectedly");
            errors = errors + 1;
        end

        do_reset;

        // --- Test 3: I_syn = 1.5 once -> fires immediately ---
        $display("Test 3: I_syn = 1.5 (0x0180) once");
        fired = 1'b0;
        do_step(16'h0180);
        if (fired)
            $display("PASS: Test 3 neuron fired immediately");
        else begin
            $display("FAIL: Test 3 neuron did not fire");
            errors = errors + 1;
        end

        if (errors == 0)
            $display("ALL TESTS PASSED (tb_lif_core)");
        else
            $display("%0d TEST(S) FAILED (tb_lif_core)", errors);
        $finish;
    end

endmodule

`default_nettype wire
