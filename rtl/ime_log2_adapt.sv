// ime_log2_adapt.sv
// Adaptive log2 approximation stage combining LZC, LUT, and optional piecewise-linear refinement.
// Decides whether to enable the gated PWL stage based on the delta threshold configuration.
// Implements a lightweight MSB-based log approximation with configurable Δ gating
// and epsilon flooring to mirror the adaptive log2 stage behaviour for smoke testing.

module ime_log2_adapt #(
  parameter int W_P      = 16,
  parameter int W_LOG    = 16,
  parameter int W_ACC    = 32,
  parameter int LUT_SIZE = 256,
  parameter int PWL_SEG  = 2,
  parameter int K_MAX    = 4096
) (
  input  logic                   clk,
  input  logic                   rst_n,

  // Input handshake from stream interface
  input  logic                   in_valid,
  output logic                   in_ready,
  input  logic [W_P-1:0]         in_prob_p,
  input  logic [W_P-1:0]         in_prob_q,
  input  logic [W_LOG-1:0]       in_score,
  input  logic [7:0]             in_tuser,
  input  logic                   in_last,
  input  logic                   in_poison,

  // Configuration and gating controls
  input  logic [7:0]             lut_size_cfg,
  input  logic [1:0]             pwl_segments_cfg,
  input  logic [15:0]            delta_thresh,
  input  logic [15:0]            epsilon_q,

  // Output handshake toward core operations
  output logic                   out_valid,
  input  logic                   out_ready,
  output logic [W_LOG-1:0]       out_log_p,
  output logic [W_LOG-1:0]       out_log_q,
  output logic [W_LOG-1:0]       out_log_score,
  output logic [W_P-1:0]         out_prob_p,
  output logic [W_P-1:0]         out_prob_q,
  output logic [7:0]             out_tuser,
  output logic                   out_last,
  output logic                   out_use_pwl,
  output logic                   out_poison
);

  // Simple helper returning an integer log2 approximation based on the position
  // of the most-significant 1 bit. This provides a monotonic estimate that is
  // sufficient for the smoke RTL skeleton and keeps the datapath synthesizable.
  function automatic logic [W_LOG-1:0] log2_msb(input logic [W_P-1:0] value);
    logic [W_LOG-1:0] result;
    logic [31:0]      idx_vec;
    int               msb_idx;

    result  = '0;
    idx_vec = '0;
    msb_idx = -1;

    for (int i = W_P-1; i >= 0; i--) begin
      if (value[i] && msb_idx < 0) begin
        msb_idx = i;
      end
    end

    if (msb_idx >= 0) begin
      idx_vec = msb_idx;
      result  = idx_vec[W_LOG-1:0];
    end
    return result;
  endfunction

  // Absolute difference helper used for Δ gating.
  function automatic logic [W_P:0] abs_diff(
    input logic [W_P-1:0] lhs,
    input logic [W_P-1:0] rhs
  );
    logic [W_P:0] diff_pos;
    logic [W_P:0] diff_neg;
    diff_pos = {1'b0, lhs} - {1'b0, rhs};
    diff_neg = {1'b0, rhs} - {1'b0, lhs};
    return (lhs >= rhs) ? diff_pos : diff_neg;
  endfunction

  logic [W_LOG-1:0] log_p_reg;
  logic [W_LOG-1:0] log_q_reg;
  logic [W_LOG-1:0] log_score_reg;
  logic [W_P-1:0]   prob_p_reg;
  logic [W_P-1:0]   prob_q_reg;
  logic [7:0]       tuser_reg;
  logic             last_reg;
  logic             use_pwl_reg;
  logic             poison_reg;
  logic             stage_valid;

  logic [15:0]      delta_thresh_local;
  logic [W_P-1:0]   epsilon_q_local;
  logic [W_P:0]     delta_thresh_ext;

  assign in_ready  = !stage_valid || (stage_valid && out_ready);
  assign out_valid = stage_valid;

  assign out_log_p     = log_p_reg;
  assign out_log_q     = log_q_reg;
  assign out_log_score = log_score_reg;
  assign out_prob_p    = prob_p_reg;
  assign out_prob_q    = prob_q_reg;
  assign out_tuser     = tuser_reg;
  assign out_last      = last_reg;
  assign out_use_pwl   = use_pwl_reg;
  assign out_poison    = poison_reg;

  // Hold configuration locally to simplify timing.
  always_comb begin
    delta_thresh_local = delta_thresh;
    if (W_P >= 16) begin
      epsilon_q_local = {{(W_P-16){1'b0}}, epsilon_q};
    end else begin
      epsilon_q_local = epsilon_q[W_P-1:0];
    end

    if (W_P + 1 >= 16) begin
      delta_thresh_ext = {{(W_P+1-16){1'b0}}, delta_thresh_local};
    end else begin
      delta_thresh_ext = delta_thresh_local[W_P:0];
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      log_p_reg     <= '0;
      log_q_reg     <= '0;
      log_score_reg <= '0;
      prob_p_reg    <= '0;
      prob_q_reg    <= '0;
      tuser_reg     <= '0;
      last_reg      <= 1'b0;
      use_pwl_reg   <= 1'b0;
      poison_reg    <= 1'b0;
      stage_valid   <= 1'b0;
    end else begin
      if (in_valid && in_ready) begin
        logic [W_P-1:0] prob_q_floor;
        logic [W_P:0]   delta_value;
        logic           has_pwl_segments;
        logic           lut_enable;

        has_pwl_segments = (pwl_segments_cfg != 0);
        lut_enable       = (lut_size_cfg != 8'd0);
        prob_q_floor     = (in_prob_q < epsilon_q_local) ? epsilon_q_local : in_prob_q;
        delta_value      = abs_diff(in_prob_p, prob_q_floor);

        prob_p_reg    <= in_prob_p;
        prob_q_reg    <= prob_q_floor;
        log_p_reg     <= log2_msb(in_prob_p);
        log_q_reg     <= log2_msb(prob_q_floor);
        // Upstream score is already log-scaled; re-log only for basic sanity.
        log_score_reg <= log2_msb(in_score);
        tuser_reg     <= in_tuser;
        last_reg      <= in_last;
        use_pwl_reg   <= has_pwl_segments && lut_enable && (delta_value > delta_thresh_ext);
        poison_reg    <= in_poison;
        stage_valid   <= 1'b1;
      end

      if (stage_valid && out_ready) begin
        stage_valid <= 1'b0;
      end

      if (poison_reg) begin
        // Once poison is asserted within the stage, keep it sticky until the
        // transaction is consumed downstream. This honours fail-closed flows.
        poison_reg <= 1'b1;
      end
    end
  end

endmodule : ime_log2_adapt

