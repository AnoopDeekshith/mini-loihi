// Phase 2A — Module 1: timestep_ctrl
// Clock-enabled timestep sequencer. Each *enabled* clock advances one timestep:
// `tick` pulses during each active timestep (step_count = 0 .. n_steps-1), and
// when the counter reaches n_steps it pulses `done` for one enabled cycle and
// wraps back to 0 to begin the next inference. Mirrors snnTorch's
// `for step in range(n_steps)`.
//
// `en` lets a master controller advance the counter exactly once per *completed*
// timestep on the main clock (no gated clock). Hold `en` high for free-running
// behavior. When `en` is low the counter holds (done/step_count retain value).

`default_nettype none

module timestep_ctrl (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       en,           // advance enable (one pulse per timestep)
    input  wire [7:0] n_steps,      // total timesteps (e.g. 20 for Iris)
    output reg        tick,         // pulses during each enabled timestep
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
        end else if (en) begin
            if (cnt == n_steps) begin
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
        end else begin
            // Not enabled: hold cnt/done/step_count; tick is a per-step pulse.
            tick <= 1'b0;
        end
    end

endmodule

`default_nettype wire
