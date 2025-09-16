// ime_fisher.sv
// Specialized datapath support for Fisher score accumulation within the IME core stage.
// Computes squared score terms and optional two-pass accumulation based on configuration.
// Provides single-stage Fisher score accumulation with EXACT1 checks to integrate into the
// skeleton core pipeline while maintaining poison-aware handshaking.

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

  function automatic logic signed [W_ACC-1:0] extend_square(input logic [2*W_LOG-1:0] value);
    logic signed [W_ACC-1:0] result;
    if (W_ACC > 2*W_LOG) begin
      result = $signed({{(W_ACC-2*W_LOG){1'b0}}, value});
    end else begin
      result = $signed(value[W_ACC-1:0]);
    end
    return result;
  endfunction

  logic                   stage_valid;
  logic [W_ACC-1:0]       fisher_reg;
  logic                   last_reg;
  logic                   poison_reg;

  assign in_ready        = !stage_valid || (stage_valid && out_ready);
  assign out_valid       = stage_valid;
  assign out_fisher_term = fisher_reg;
  assign out_last        = last_reg;
  assign out_poison      = poison_reg;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      stage_valid <= 1'b0;
      fisher_reg  <= '0;
      last_reg    <= 1'b0;
      poison_reg  <= 1'b0;
    end else begin
      if (in_valid && in_ready) begin
        logic                  fisher_active;
        logic [2*W_LOG-1:0]    score_sq;
        logic signed [W_ACC-1:0] prob_ext;
        logic signed [W_ACC-1:0] score_sq_ext;
        logic signed [2*W_ACC-1:0] fisher_full;
        logic                   mode_error;

        fisher_active = mode_onehot[4];
        score_sq      = in_score * in_score;
        prob_ext      = extend_prob(in_prob);
        score_sq_ext  = extend_square(score_sq);
        fisher_full   = prob_ext * score_sq_ext;
        mode_error    = (mode_onehot != '0) && !mode_exact1(mode_onehot);

        fisher_reg <= fisher_active ? fisher_full[W_ACC-1:0] : '0;
        last_reg   <= in_last;
        poison_reg <= in_poison || mode_error;
        stage_valid<= 1'b1;
      end

      if (stage_valid && out_ready) begin
        stage_valid <= 1'b0;
        last_reg    <= 1'b0;
        // Poison sticks until the transaction is consumed, after which it clears.
        poison_reg  <= 1'b0;
      end
    end
  end

endmodule : ime_fisher

