// Phase 2A — Module 2: weight_rom
// Synchronous (1-cycle latency) read-only memory holding Q8.8 weights, the
// hardware equivalent of an nn.Linear weight matrix. Initialized from a hex
// file via $readmemh. MEM_FILE is a parameter so the same module serves both
// layers (override for layer2). Addressing is row-major: addr = pre*N_POST+post.

`default_nettype none

module weight_rom #(
    parameter N_PRE    = 8,
    parameter N_POST   = 4,
    parameter DATA_W   = 16,                                  // Q8.8
    parameter MEM_FILE = "../../hardware/mem/layer1_weights.hex"
) (
    input  wire                              clk,
    input  wire [$clog2(N_PRE*N_POST)-1:0]   addr,
    output reg  [DATA_W-1:0]                 data_out
);

    localparam DEPTH = N_PRE * N_POST;

    reg [DATA_W-1:0] mem [0:DEPTH-1];

    initial begin
        $readmemh(MEM_FILE, mem);
    end

    // Registered read => 1-cycle latency.
    always @(posedge clk) begin
        data_out <= mem[addr];
    end

endmodule

`default_nettype wire
