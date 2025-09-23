// ime_fisher.sv
// Specialized datapath support for Fisher score accumulation within the IME core stage.
// Computes squared score terms and optional two-pass accumulation based on configuration.
// TODO: Implement score buffering, NR-based normalization, and integration hooks for the core stage.

module ime_fisher #(
  parameter int W_P      = 16,
  parameter int W_LOG    = 16,
  parameter int W_ACC    = 32,
  parameter int LUT_SIZE = 256,
  parameter int PWL_SEG  = 2,
  parameter int K_MAX    = 4096
) (
  input  logic                   clk,
  input  logic                   rst_n,

  // Interface from core stage when Fisher mode is active
  input  logic                   in_valid,
  output logic                   in_ready,
  input  logic [W_P-1:0]         in_prob,
  input  logic [W_LOG-1:0]       in_score,
  input  logic                   in_last,
  input  logic                   in_poison,

  // Configuration inputs
  input  logic [4:0]             mode_onehot,

  // Output toward accumulator or core
  output logic                   out_valid,
  input  logic                   out_ready,
  output logic [W_ACC-1:0]       out_fisher_term,
  output logic                   out_last,
  output logic                   out_poison
);

  // TODO: Add score squaring pipeline and two-pass mode handling.

endmodule : ime_fisher

