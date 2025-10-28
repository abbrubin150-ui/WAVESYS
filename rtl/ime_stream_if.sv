// ime_stream_if.sv
// Front-end stream interface handling framing, epsilon floor, and poison propagation for the IME pipeline.
// Accepts AXI-Stream style traffic, enforces frame boundaries, and forwards normalized samples downstream.
// Implements Stage S0: frame counting, epsilon flooring, and 1-cycle latency pipeline with ready/valid flow control.

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

  // =========================================================================
  // Data unpacking from AXI-Stream tdata
  // =========================================================================
  logic [W_P-1:0]   in_prob_p;
  logic [W_P-1:0]   in_prob_q;
  logic [W_LOG-1:0] in_score;

  // tdata format: {prob_p, prob_q, score}
  assign {in_prob_p, in_prob_q, in_score} = s_axis_tdata;

  // =========================================================================
  // Pipeline registers and control
  // =========================================================================
  logic [W_P-1:0]   prob_p_reg;
  logic [W_P-1:0]   prob_q_reg;
  logic [W_LOG-1:0] score_reg;
  logic [7:0]       tuser_reg;
  logic             last_reg;
  logic             poison_reg;
  logic             valid_reg;

  logic [15:0]      frame_count_reg;
  logic             frame_start_reg;
  logic             frame_end_reg;

  // =========================================================================
  // Epsilon floor configuration
  // =========================================================================
  logic [W_P-1:0]   epsilon_local;

  always_comb begin
    if (W_P >= 16) begin
      epsilon_local = {{(W_P-16){1'b0}}, epsilon_q};
    end else begin
      epsilon_local = epsilon_q[W_P-1:0];
    end
  end

  // =========================================================================
  // Ready/Valid handshaking
  // =========================================================================
  assign s_axis_tready = !valid_reg || (valid_reg && out_ready);
  assign out_valid     = valid_reg;

  // =========================================================================
  // Output assignments
  // =========================================================================
  assign out_prob_p    = prob_p_reg;
  assign out_prob_q    = prob_q_reg;
  assign out_score     = score_reg;
  assign out_tuser     = tuser_reg;
  assign out_last      = last_reg;
  assign out_poison    = poison_reg;
  assign frame_start   = frame_start_reg;
  assign frame_end     = frame_end_reg;

  // =========================================================================
  // Frame counting and epsilon floor pipeline
  // =========================================================================
  logic [15:0] frame_len_eff;
  logic [16:0] frame_count_ext;
  logic        is_frame_start;
  logic [W_P-1:0] prob_q_floored;

  assign frame_len_eff = (frame_len == 16'd0) ? 16'd1 : frame_len;
  assign frame_count_ext = {1'b0, frame_count_reg};
  assign is_frame_start = (frame_count_reg == 16'd0);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      prob_p_reg       <= '0;
      prob_q_reg       <= '0;
      score_reg        <= '0;
      tuser_reg        <= '0;
      last_reg         <= 1'b0;
      poison_reg       <= 1'b0;
      valid_reg        <= 1'b0;
      frame_count_reg  <= 16'd0;
      frame_start_reg  <= 1'b0;
      frame_end_reg    <= 1'b0;
    end else begin
      // Clear frame markers every cycle (pulse signals)
      frame_start_reg <= 1'b0;
      frame_end_reg   <= 1'b0;

      // Pipeline stage: input → registered output
      if (s_axis_tvalid && s_axis_tready) begin
        logic is_last_of_frame;
        logic [16:0] next_count;

        // Apply epsilon floor to prob_q
        prob_q_floored = (in_prob_q < epsilon_local) ? epsilon_local : in_prob_q;

        // Determine if this is last sample in frame
        next_count = frame_count_ext + 17'd1;
        is_last_of_frame = s_axis_tlast || (next_count >= {1'b0, frame_len_eff});

        // Register data
        prob_p_reg  <= in_prob_p;
        prob_q_reg  <= prob_q_floored;
        score_reg   <= in_score;
        tuser_reg   <= s_axis_tuser;
        last_reg    <= is_last_of_frame;
        poison_reg  <= poison_inject;
        valid_reg   <= 1'b1;

        // Update frame counter
        if (is_frame_start) begin
          frame_start_reg <= 1'b1;
        end

        if (is_last_of_frame) begin
          frame_count_reg <= 16'd0;
          frame_end_reg   <= 1'b1;
        end else begin
          frame_count_reg <= next_count[15:0];
        end
      end

      // Consume output when downstream is ready
      if (valid_reg && out_ready) begin
        valid_reg <= 1'b0;
      end
    end
  end

endmodule : ime_stream_if

