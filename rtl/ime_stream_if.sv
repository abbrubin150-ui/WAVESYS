// ime_stream_if.sv
// Front-end stream interface handling framing, epsilon floor, and poison propagation for the IME pipeline.
// Accepts AXI-Stream style traffic, enforces frame boundaries, and forwards normalized samples downstream.
// Implements buffering, frame tracking, epsilon floor application, and constant-time throttling
// to mirror the freeze-pack expectations for early integration.

module ime_stream_if #(
  parameter int W_P      = 16,
  parameter int W_LOG    = 16,
  parameter int W_ACC    = 32,
  parameter int LUT_SIZE = 256,
  parameter int PWL_SEG  = 2,
  parameter int K_MAX    = 4096
) (
  input  logic                       clk,
  input  logic                       rst_n,

  // AXI-Stream input from system or BIST
  input  logic [W_P*2+W_LOG-1:0]     s_axis_tdata,
  input  logic [7:0]                 s_axis_tuser,
  input  logic                       s_axis_tvalid,
  output logic                       s_axis_tready,
  input  logic                       s_axis_tlast,

  // Downstream handshake toward adaptive log2 stage
  output logic                       out_valid,
  input  logic                       out_ready,
  output logic [W_P-1:0]             out_prob_p,
  output logic [W_P-1:0]             out_prob_q,
  output logic [W_LOG-1:0]           out_score,
  output logic [7:0]                 out_tuser,
  output logic                       out_last,
  output logic                       out_poison,

  // Configuration inputs
  input  logic [15:0]                frame_len,
  input  logic [15:0]                epsilon_q,
  input  logic [13:0]                const_time_cycles,

  // Flow control and framing indicators
  output logic                       frame_start,
  output logic                       frame_end,
  input  logic                       poison_inject
);

  localparam int unsigned EPS_PAD = (W_P > 16) ? (W_P - 16) : 0;

  logic [W_P-1:0]   prob_p_reg;
  logic [W_P-1:0]   prob_q_reg;
  logic [W_LOG-1:0] score_reg;
  logic [7:0]       tuser_reg;
  logic             last_reg;
  logic             poison_reg;
  logic             frame_start_reg;
  logic             frame_end_reg;
  logic             stage_valid;
  logic [15:0]      frame_count_reg;
  logic [13:0]      delay_reg;

  logic [W_P-1:0]   epsilon_local;
  logic [15:0]      frame_len_eff;
  logic             out_fire;
  logic             accept_sample;

  assign epsilon_local = (W_P > 16) ? {{EPS_PAD{1'b0}}, epsilon_q} : epsilon_q[W_P-1:0];
  assign frame_len_eff = (frame_len == 16'd0) ? 16'd1 : frame_len;

  assign out_valid     = stage_valid && (delay_reg == 14'd0);
  assign out_prob_p    = prob_p_reg;
  assign out_prob_q    = prob_q_reg;
  assign out_score     = score_reg;
  assign out_tuser     = tuser_reg;
  assign out_last      = last_reg;
  assign out_poison    = poison_reg;
  assign frame_start   = frame_start_reg;
  assign frame_end     = frame_end_reg;

  assign out_fire      = out_valid && out_ready;
  assign accept_sample = s_axis_tvalid && s_axis_tready;

  assign s_axis_tready = !stage_valid || out_fire;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      prob_p_reg      <= '0;
      prob_q_reg      <= '0;
      score_reg       <= '0;
      tuser_reg       <= '0;
      last_reg        <= 1'b0;
      poison_reg      <= 1'b0;
      frame_start_reg <= 1'b0;
      frame_end_reg   <= 1'b0;
      stage_valid     <= 1'b0;
      frame_count_reg <= 16'd0;
      delay_reg       <= 14'd0;
    end else begin
      if (accept_sample) begin
        logic [W_P-1:0] prob_p_in;
        logic [W_P-1:0] prob_q_in;
        logic [W_LOG-1:0] score_in;
        logic [15:0] next_index;
        logic        is_frame_end;

        prob_p_in = s_axis_tdata[W_P*2+W_LOG-1:W_P+W_LOG];
        prob_q_in = s_axis_tdata[W_P+W_LOG-1:W_LOG];
        score_in  = s_axis_tdata[W_LOG-1:0];

        next_index   = frame_count_reg + 16'd1;
        is_frame_end = s_axis_tlast || (next_index >= frame_len_eff);

        prob_p_reg      <= prob_p_in;
        prob_q_reg      <= (prob_q_in < epsilon_local) ? epsilon_local : prob_q_in;
        score_reg       <= score_in;
        tuser_reg       <= s_axis_tuser;
        last_reg        <= is_frame_end;
        poison_reg      <= poison_inject;
        frame_start_reg <= (frame_count_reg == 16'd0);
        frame_end_reg   <= is_frame_end;
        stage_valid     <= 1'b1;
        delay_reg       <= const_time_cycles;
        frame_count_reg <= is_frame_end ? 16'd0 : next_index;
      end else begin
        frame_start_reg <= 1'b0;
        frame_end_reg   <= 1'b0;
      end

      if (stage_valid && (delay_reg != 14'd0)) begin
        delay_reg <= delay_reg - 14'd1;
      end else if (!stage_valid) begin
        delay_reg <= 14'd0;
      end

      if (out_fire) begin
        stage_valid <= 1'b0;
        last_reg    <= 1'b0;
        poison_reg  <= 1'b0;
      end
    end
  end

endmodule : ime_stream_if

