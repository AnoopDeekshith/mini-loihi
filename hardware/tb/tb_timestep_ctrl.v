// Testbench for timestep_ctrl (Phase 2A).
// Drives n_steps = 5 and verifies: tick fires exactly 5 times, step_count
// increments 0..4, and done pulses exactly once at the end. Outputs are
// sampled at the negative clock edge so the registered DUT outputs are stable.

`timescale 1ns/1ps
`default_nettype none

module tb_timestep_ctrl ();

    reg        clk;
    reg        rst_n;
    reg  [7:0] n_steps;
    wire       tick;
    wire       done;
    wire [7:0] step_count;

    integer tick_count = 0;
    integer done_count = 0;
    integer errors     = 0;
    reg [7:0] expected_step = 0;

    timestep_ctrl dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .n_steps    (n_steps),
        .tick       (tick),
        .done       (done),
        .step_count (step_count)
    );

    // 10ns clock
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // Sample DUT outputs at negedge (registered values settled).
    always @(negedge clk) begin
        if (rst_n) begin
            if (tick) begin
                $display("[%0t] TICK #%0d  step_count=%0d", $time, tick_count,
                         step_count);
                if (step_count !== expected_step) begin
                    $display("  FAIL: step_count=%0d, expected %0d",
                             step_count, expected_step);
                    errors = errors + 1;
                end
                tick_count    = tick_count + 1;
                expected_step = expected_step + 1;
            end
            if (done) begin
                $display("[%0t] DONE pulse", $time);
                done_count = done_count + 1;

                // Final checks once the first run completes.
                if (tick_count == 5)
                    $display("PASS: tick fired exactly 5 times");
                else begin
                    $display("FAIL: tick fired %0d times, expected 5",
                             tick_count);
                    errors = errors + 1;
                end
                if (done_count == 1)
                    $display("PASS: done fired exactly once");
                else begin
                    $display("FAIL: done fired %0d times, expected 1",
                             done_count);
                    errors = errors + 1;
                end

                if (errors == 0)
                    $display("ALL TESTS PASSED (tb_timestep_ctrl)");
                else
                    $display("%0d TEST(S) FAILED (tb_timestep_ctrl)", errors);
                $finish;
            end
        end
    end

    initial begin
        n_steps = 8'd5;
        rst_n   = 1'b0;
        #12 rst_n = 1'b1;   // deassert reset after ~1 cycle

        // Safety timeout.
        #1000;
        $display("FAIL: timeout — done never fired");
        $finish;
    end

endmodule

`default_nettype wire
