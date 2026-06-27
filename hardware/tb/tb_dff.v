// Testbench for the parameterized D flip-flop (Phase 0 warmup).
// Exercises async reset, basic capture, and back-to-back captures, printing a
// PASS/FAIL line per check.

`timescale 1ns/1ps
`default_nettype none

module tb_dff ();

    localparam WIDTH = 8;

    reg              clk;
    reg              rst_n;
    reg  [WIDTH-1:0] d;
    wire [WIDTH-1:0] q;

    integer errors = 0;

    // Device under test
    dff #(.WIDTH(WIDTH)) dut (
        .clk   (clk),
        .rst_n (rst_n),
        .d     (d),
        .q     (q)
    );

    // 10ns period clock
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // Simple check helper
    task check;
        input [WIDTH-1:0] got;
        input [WIDTH-1:0] exp;
        input [255:0]     name;
        begin
            if (got === exp) begin
                $display("PASS: %0s (q=0x%02h)", name, got);
            end else begin
                $display("FAIL: %0s (q=0x%02h, expected 0x%02h)", name, got, exp);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        // --- Test 1: async reset clears q ---
        rst_n = 1'b0;
        d     = 8'hAA;
        #3;                       // mid-cycle, before any clock edge
        check(q, 8'h00, "async reset clears q");

        // --- Test 2: basic capture after reset deassert ---
        @(negedge clk);
        rst_n = 1'b1;
        d     = 8'h3C;
        @(posedge clk); #1;
        check(q, 8'h3C, "basic capture d=0x3C");

        // --- Test 3: back-to-back captures ---
        d = 8'h5A;
        @(posedge clk); #1;
        check(q, 8'h5A, "back-to-back capture d=0x5A");

        d = 8'hF0;
        @(posedge clk); #1;
        check(q, 8'hF0, "back-to-back capture d=0xF0");

        // --- Test 4: async reset overrides data mid-stream ---
        d     = 8'hFF;
        rst_n = 1'b0;
        #1;
        check(q, 8'h00, "async reset overrides data");
        rst_n = 1'b1;

        // --- Summary ---
        if (errors == 0)
            $display("ALL TESTS PASSED (tb_dff)");
        else
            $display("%0d TEST(S) FAILED (tb_dff)", errors);

        $finish;
    end

endmodule

`default_nettype wire
