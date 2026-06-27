// Testbench for spike_router (Phase 2B).
// Applies known spike patterns, pulses tick, and checks that spike_out is a
// 1-cycle-delayed registered copy of spike_in and that route_valid pulses one
// cycle after tick.

`timescale 1ns/1ps
`default_nettype none

module tb_spike_router ();

    localparam N_IN  = 4;
    localparam N_OUT = 4;

    reg              clk;
    reg              rst_n;
    reg              tick;
    reg  [N_IN-1:0]  spike_in;
    wire [N_OUT-1:0] spike_out;
    wire             route_valid;

    integer errors = 0;

    spike_router #(.N_IN(N_IN), .N_OUT(N_OUT)) dut (
        .clk         (clk),
        .rst_n       (rst_n),
        .tick        (tick),
        .spike_in    (spike_in),
        .spike_out   (spike_out),
        .route_valid (route_valid)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    // Present a pattern, pulse tick for one cycle, then check the registered
    // outputs one cycle later (when route_valid should be high).
    task route_check;
        input [N_IN-1:0] pat;
        begin
            @(negedge clk);
            spike_in = pat;
            tick     = 1'b1;
            @(posedge clk);          // router registers spike_in, schedules route_valid
            @(negedge clk);
            tick     = 1'b0;
            // Now spike_out should equal pat and route_valid should be high.
            if (spike_out === pat)
                $display("PASS: spike_out=0b%04b matches spike_in", spike_out);
            else begin
                $display("FAIL: spike_out=0b%04b, expected 0b%04b",
                         spike_out, pat);
                errors = errors + 1;
            end
            if (route_valid === 1'b1)
                $display("PASS: route_valid asserted");
            else begin
                $display("FAIL: route_valid not asserted");
                errors = errors + 1;
            end
            // One cycle later route_valid should drop.
            @(posedge clk);
            @(negedge clk);
            if (route_valid === 1'b0)
                $display("PASS: route_valid is a 1-cycle pulse");
            else begin
                $display("FAIL: route_valid did not deassert");
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        tick     = 1'b0;
        spike_in = '0;
        rst_n    = 1'b0;
        repeat (2) @(negedge clk);
        rst_n    = 1'b1;

        route_check(4'b1010);
        route_check(4'b0101);
        route_check(4'b1111);

        if (errors == 0)
            $display("ALL TESTS PASSED (tb_spike_router)");
        else
            $display("%0d TEST(S) FAILED (tb_spike_router)", errors);
        $finish;
    end

endmodule

`default_nettype wire
