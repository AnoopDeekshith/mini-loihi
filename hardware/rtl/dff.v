// Phase 0 — Verilog warmup: parameterized D flip-flop.
// Synchronous data capture on the rising clock edge, with an active-low
// asynchronous reset that clears q to 0.

`default_nettype none

module dff #(
    parameter WIDTH = 8
) (
    input  wire             clk,
    input  wire             rst_n,   // active-low async reset
    input  wire [WIDTH-1:0] d,
    output reg  [WIDTH-1:0] q
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            q <= {WIDTH{1'b0}};
        else
            q <= d;
    end

endmodule

`default_nettype wire
