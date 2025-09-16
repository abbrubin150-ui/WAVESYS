// ime_coreop.sv
// Core computation stage implementing entropy, cross-entropy, KL, MI, and Fisher metrics.
// Selects mode-specific datapaths, manages Newton-Raphson refinements, and drives clock-gating enables.
// Implements a simple shared-multiplier datapath with EXACT1 decoding and constant
// latency sequencing to exercise entropy/KL/MI/Fisher flows in the skeleton design.

module ime_coreop #(
  parameter int W_P      = 16,
  parameter int W_LOG    = 16,
  parameter int W_ACC    = 32,
  parameter int LUT_SIZE = 256,
  parameter int PWL_SEG  = 2,
  parameter int K_MAX    = 4096
) (
  input  logic                   clk,
  input  logic                   rst_n,

  // Input handshake from adaptive log2 stage
  input  logic                   in_valid,
  output logic                   in_ready,
  input  logic [W_LOG-1:0]       in_log_p,
  input  logic [W_LOG-1:0]       in_log_q,
  input  logic [W_LOG-1:0]       in_log_score,
  input  logic [W_P-1:0]         in_prob_p,
  input  logic [W_P-1:0]         in_prob_q,
  input  logic [7:0]             in_tuser,
  input  logic                   in_last,
  input  logic                   in_use_pwl,
  input  logic                   in_poison,

  // Configuration inputs
  input  logic [4:0]             mode_onehot,
  input  logic [13:0]            const_time_cycles,

  // Gating outputs (cen_* signals per mode)
  output logic                   cen_entropy,
  output logic                   cen_cross_entropy,
  output logic                   cen_kl,
  output logic                   cen_mi,
  output logic                   cen_fisher,

  // Output handshake toward accumulator
  output logic                   out_valid,
  input  logic                   out_ready,
  output logic [W_ACC-1:0]       out_partial_acc,
  output logic [7:0]             out_tuser,
  output logic                   out_last,
  output logic                   out_poison
);

  // Helper returning TRUE when the mode field is EXACT1 encoded. Violations
  // trigger poison propagation to honour fail-closed behaviour.
  function automatic logic mode_exact1(input logic [4:0] mode);
    logic [4:0] masked;
    masked = mode & (mode - 5'd1);
    return (mode != '0) && (masked == '0);
  endfunction

  function automatic logic signed [W_ACC-1:0] extend_prob(input logic [W_P-1:0] value);
    logic signed [W_ACC-1:0] result;
    if (W_ACC > W_P) begin
      result = $signed({{(W_ACC-W_P){1'b0}}, value});
    end else begin
      result = $signed(value[W_ACC-1:0]);
    end
    return result;
  endfunction

  function automatic logic signed [W_ACC-1:0] extend_log(input logic [W_LOG-1:0] value);
    logic signed [W_ACC-1:0] result;
    if (W_ACC > W_LOG) begin
      result = $signed({{(W_ACC-W_LOG){1'b0}}, value});
    end else begin
      result = $signed(value[W_ACC-1:0]);
    end
    return result;
  endfunction

  function automatic logic [W_ACC-1:0] compute_metric(
    input logic [4:0]             mode,
    input logic [W_LOG-1:0]       log_p,
    input logic [W_LOG-1:0]       log_q,
    input logic [W_LOG-1:0]       log_score,
    input logic [W_P-1:0]         prob_p,
    input logic [W_P-1:0]         prob_q
  );
    logic signed [W_ACC-1:0]      p_ext;
    logic signed [W_ACC-1:0]      q_ext;
    logic signed [W_ACC-1:0]      log_p_ext;
    logic signed [W_ACC-1:0]      log_q_ext;
    logic signed [W_ACC-1:0]      log_score_ext;
    logic signed [2*W_ACC-1:0]    mult_term;
    logic signed [W_ACC-1:0]      diff_term;
    logic [W_ACC-1:0]             result;

    p_ext         = extend_prob(prob_p);
    q_ext         = extend_prob(prob_q);
    log_p_ext     = extend_log(log_p);
    log_q_ext     = extend_log(log_q);
    log_score_ext = extend_log(log_score);
    mult_term     = '0;
    diff_term     = log_p_ext - log_q_ext;
    result        = '0;

    if (mode[0]) begin
      mult_term = p_ext * log_p_ext;
      result    = -$signed(mult_term[W_ACC-1:0]);
    end else if (mode[1]) begin
      mult_term = p_ext * log_q_ext;
      result    = -$signed(mult_term[W_ACC-1:0]);
    end else if (mode[2]) begin
      mult_term = p_ext * diff_term;
      result    = $signed(mult_term[W_ACC-1:0]);
    end else if (mode[3]) begin
      mult_term = p_ext * log_score_ext;
      result    = $signed(mult_term[W_ACC-1:0]);
    end else if (mode[4]) begin
      // Fisher mode uses the log_score input as a squared-score proxy when the
      // dedicated ime_fisher block is bypassed. This keeps the pipeline active
      // for smoke testing and still honours constant-time sequencing.
      mult_term = p_ext * log_score_ext;
      result    = $signed(mult_term[W_ACC-1:0]);
    end
    return result;
  endfunction

  logic [4:0]             mode_reg;
  logic [7:0]             tuser_reg;
  logic                   last_reg;
  logic                   poison_reg;
  logic [W_ACC-1:0]       partial_reg;
  logic                   busy_reg;
  logic                   result_valid_reg;
  logic [13:0]            countdown_reg;

  assign in_ready        = !busy_reg;
  assign out_valid       = result_valid_reg;
  assign out_partial_acc = partial_reg;
  assign out_tuser       = tuser_reg;
  assign out_last        = last_reg;
  assign out_poison      = poison_reg;

  assign cen_entropy        = busy_reg && mode_reg[0];
  assign cen_cross_entropy  = busy_reg && mode_reg[1];
  assign cen_kl             = busy_reg && mode_reg[2];
  assign cen_mi             = busy_reg && mode_reg[3];
  assign cen_fisher         = busy_reg && mode_reg[4];

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      mode_reg          <= '0;
      tuser_reg         <= '0;
      last_reg          <= 1'b0;
      poison_reg        <= 1'b0;
      partial_reg       <= '0;
      busy_reg          <= 1'b0;
      result_valid_reg  <= 1'b0;
      countdown_reg     <= '0;
    end else begin
      if (!busy_reg && in_valid && in_ready) begin
        logic [4:0] mode_local;

        mode_local      = mode_onehot;
        mode_reg        <= mode_local;
        tuser_reg       <= in_tuser;
        last_reg        <= in_last;
        partial_reg     <= compute_metric(mode_local, in_log_p, in_log_q, in_log_score, in_prob_p, in_prob_q);
        busy_reg        <= 1'b1;
        result_valid_reg<= 1'b0;
        countdown_reg   <= const_time_cycles;
        poison_reg      <= in_poison || !mode_exact1(mode_local);
      end else if (busy_reg && !result_valid_reg) begin
        if (countdown_reg == 14'd0) begin
          result_valid_reg <= 1'b1;
        end else begin
          countdown_reg <= countdown_reg - 14'd1;
        end
      end else if (result_valid_reg && out_ready) begin
        result_valid_reg <= 1'b0;
        busy_reg         <= 1'b0;
        poison_reg       <= 1'b0;
      end

    end
  end

endmodule : ime_coreop

