// Testbench for weight_rom (Phase 2A).
// Uses a committed deterministic fixture (tb_weight_rom.hex, addr i -> 0x1000+i)
// via the MEM_FILE parameter override so expected values are known regardless
// of the trained weights. Verifies the 1-cycle registered read latency at
// addresses 0, 1, 5 and that distinct addresses return distinct values.

`timescale 1ns/1ps
`default_nettype none

module tb_weight_rom ();

    localparam N_PRE  = 8;
    localparam N_POST = 4;
    localparam DATA_W = 16;
    localparam AW     = $clog2(N_PRE * N_POST);  // 5

    reg               clk;
    reg  [AW-1:0]     addr;
    wire [DATA_W-1:0] data_out;

    integer errors = 0;
    reg [DATA_W-1:0] v0, v1, v5;

    weight_rom #(
        .N_PRE    (N_PRE),
        .N_POST   (N_POST),
        .DATA_W   (DATA_W),
        .MEM_FILE ("hardware/mem/tb_weight_rom.hex")
    ) dut (
        .clk      (clk),
        .addr     (addr),
        .data_out (data_out)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    // Registered read: present addr, capture on the next posedge, then check.
    task read_addr;
        input  [AW-1:0]     a;
        output [DATA_W-1:0] captured;
        begin
            @(negedge clk);
            addr = a;
            @(posedge clk);   // ROM registers mem[addr]
            @(negedge clk);   // data_out settled
            captured = data_out;
        end
    endtask

    task expect_eq;
        input [DATA_W-1:0] got;
        input [DATA_W-1:0] exp;
        input [AW-1:0]     a;
        begin
            if (got === exp)
                $display("PASS: addr %0d -> 0x%04h", a, got);
            else begin
                $display("FAIL: addr %0d -> 0x%04h, expected 0x%04h",
                         a, got, exp);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        addr = 0;

        read_addr(5'd0, v0);
        expect_eq(v0, 16'h1000, 5'd0);

        read_addr(5'd1, v1);
        expect_eq(v1, 16'h1001, 5'd1);

        read_addr(5'd5, v5);
        expect_eq(v5, 16'h1005, 5'd5);

        // Distinct addresses must return distinct values.
        if (v0 !== v1 && v1 !== v5 && v0 !== v5)
            $display("PASS: distinct addresses return distinct values");
        else begin
            $display("FAIL: distinct addresses returned equal values");
            errors = errors + 1;
        end

        if (errors == 0)
            $display("ALL TESTS PASSED (tb_weight_rom)");
        else
            $display("%0d TEST(S) FAILED (tb_weight_rom)", errors);
        $finish;
    end

endmodule

`default_nettype wire
