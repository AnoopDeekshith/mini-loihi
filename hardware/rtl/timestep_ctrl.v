// Phase 2A — Module 1: timestep_ctrl
// Free-running timestep sequencer. Each clock advances one timestep: `tick`
// asserts during every active timestep (step_count = 0 .. n_steps-1), and when
// the counter reaches n_steps it pulses `done` for one cycle and wraps back to
// 0 to begin the next inference. Mirrors snnTorch's `for step in range(n_steps)`.

`default_nettype none

module timestep_ctrl (
    input  wire       clk,
    input  wire       rst_n,
    input  wire [7:0] n_steps,      // total timesteps (e.g. 20 for Iris)
    output reg        tick,         // active during each timestep
    output reg        done,         // 1-cycle pulse when all steps complete
    output reg  [7:0] step_count    // current timestep index (0 .. n_steps-1)
);

    reg [7:0] cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt        <= 8'd0;
            tick       <= 1'b0;
            done       <= 1'b0;
            step_count <= 8'd0;
        end else if (cnt == n_steps) begin
            // All timesteps done: pulse done and wrap.
            done       <= 1'b1;
            tick       <= 1'b0;
            cnt        <= 8'd0;
            step_count <= 8'd0;
        end else begin
            // Active timestep: emit tick, expose index, advance.
            done       <= 1'b0;
            tick       <= 1'b1;
            step_count <= cnt;
            cnt        <= cnt + 8'd1;
        end
    end

endmodule

`default_nettype wire
