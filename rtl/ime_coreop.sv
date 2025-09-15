// ime_coreop.sv
// Core computation stage implementing entropy, cross-entropy, KL, MI, and Fisher metrics.
// Selects mode-specific datapaths, manages Newton-Raphson refinements, and drives clock-gating enables.
// TODO: Implement mode decode, shared multipliers, and constant-time control sequencing.

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

  // TODO: Share arithmetic resources across metrics and enforce EXACT1 constant-time behavior.

endmodule : ime_coreop

