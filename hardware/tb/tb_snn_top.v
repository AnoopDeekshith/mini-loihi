// Phase 3 — Integration testbench for snn_top.
// Runs two known Iris samples through the full 8->4->2 processor as rate-coded
// spikes over ~20 timesteps and checks the predicted class (argmax of output
// spike counts):
//   - setosa     (class 0): normalized 0.22, 0.625, 0.068, 0.042
//   - versicolor (class 1): normalized 0.519, 0.333, 0.854, 0.706
// Each of the 4 features is duplicated to form the 8-input bus. Running both
// proves the network discriminates rather than always predicting one class.

`timescale 1ns/1ps
`default_nettype none

module tb_snn_top ();

    reg        clk;
    reg        rst_n;
    reg  [7:0] spike_bus;
    reg  [7:0] n_steps;
    wire [15:0] spike_count;        // flattened: class 0 in [7:0], class 1 in [15:8]
    wire       done;

    integer errors = 0;
    integer seed = 32'd2026;

    // Per-mille firing probability for each of the 8 inputs (features x2).
    integer prob [0:7];

    snn_top dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .spike_in_bus (spike_bus),
        .n_steps      (n_steps),
        .spike_count  (spike_count),
        .done         (done)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    // Generate one timestep's rate-coded spike vector from the current prob[].
    integer gi;
    integer r;
    task gen_spikes;
        begin
            for (gi = 0; gi < 8; gi = gi + 1) begin
                r = $random % 1000;
                if (r < 0) r = r + 1000;
                spike_bus[gi] = (r < prob[gi]) ? 1'b1 : 1'b0;
            end
        end
    endtask

    // Refresh the input pattern at each timestep boundary (FSM `adv` pulse).
    always @(posedge clk) begin
        if (rst_n && dut.adv)
            gen_spikes;
    end

    // Load a 4-feature normalized sample (per-mille), duplicated to 8 inputs.
    task set_sample;
        input integer p0, p1, p2, p3;
        begin
            prob[0] = p0; prob[1] = p0;
            prob[2] = p1; prob[3] = p1;
            prob[4] = p2; prob[5] = p2;
            prob[6] = p3; prob[7] = p3;
        end
    endtask

    integer pred;
    // Reset, run one full inference, report and check against expected class.
    task run_inference;
        input integer expected;
        input [127:0] name;
        begin
            rst_n     = 1'b0;
            spike_bus = 8'd0;
            gen_spikes;                 // initial pattern for timestep 0
            repeat (3) @(negedge clk);
            rst_n = 1'b1;

            wait (done == 1'b1);
            @(negedge clk);

            pred = (spike_count[7:0] >= spike_count[15:8]) ? 0 : 1;
            $display("[%0s] Class 0 spikes: %0d, Class 1 spikes: %0d, Predicted: %0d, Expected: %0d",
                     name, spike_count[7:0], spike_count[15:8], pred, expected);
            if (pred == expected)
                $display("  PASS: %0s classified as class %0d", name, expected);
            else begin
                $display("  FAIL: %0s misclassified (got %0d, expected %0d)",
                         name, pred, expected);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        r       = $random(seed);   // seed the RNG
        n_steps = 8'd20;
        rst_n   = 1'b0;

        // setosa -> class 0
        set_sample(220, 625, 68, 42);
        run_inference(0, "setosa");

        // versicolor -> class 1
        set_sample(519, 333, 854, 706);
        run_inference(1, "versicolor");

        if (errors == 0)
            $display("ALL TESTS PASSED (tb_snn_top)");
        else
            $display("%0d TEST(S) FAILED (tb_snn_top)", errors);
        $finish;
    end

    // Safety timeout.
    initial begin
        #1000000;
        $display("FAIL: timeout — done never fired");
        $finish;
    end

endmodule

`default_nettype wire
