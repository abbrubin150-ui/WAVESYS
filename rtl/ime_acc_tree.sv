// ime_acc_tree.sv
// Accumulation stage supporting sequential and tree-based reductions for configurable frame lengths.
// Reports downstream credit depth and propagates poison to enforce end-to-end validity guarantees.
// Provides sequential accumulation with frame-based credit tracking and poison propagation,
// modelling the tree accumulator behaviour for early integration and verification scaffolding.

module ime_acc_tree #(
  parameter int W_P      = 16,
  parameter int W_LOG    = 16,
  parameter int W_ACC    = 32,
  parameter int LUT_SIZE = 256,
  parameter int PWL_SEG  = 2,
  parameter int K_MAX    = 4096
) (
  input  logic                   clk,
  input  logic                   rst_n,

  // Input handshake from core operation stage
  input  logic                   in_valid,
  output logic                   in_ready,
  input  logic [W_ACC-1:0]       in_partial_acc,
  input  logic [7:0]             in_tuser,
  input  logic                   in_last,
  input  logic                   in_poison,

  // Configuration inputs
  input  logic                   tree_type,
  input  logic [15:0]            frame_len,

  // Output handshake toward final stage
  output logic                   out_valid,
  input  logic                   out_ready,
  output logic [W_ACC-1:0]       out_frame_acc,
  output logic [7:0]             out_tuser,
  output logic                   out_last,
  output logic                   out_poison,

  // Status reporting
  output logic [15:0]            credit_depth
);

  logic [W_ACC-1:0] acc_reg;
  logic [15:0]      count_reg;
  logic             poison_frame_reg;
  logic [W_ACC-1:0] out_frame_acc_reg;
  logic [7:0]       out_tuser_reg;
  logic             out_last_reg;
  logic             out_valid_reg;
  logic             out_poison_reg;
  logic [15:0]      credit_reg;

  logic [W_ACC-1:0] acc_next;
  logic [15:0]      count_next;
  logic             poison_frame_next;
  logic [W_ACC-1:0] out_frame_acc_next;
  logic [7:0]       out_tuser_next;
  logic             out_last_next;
  logic             out_valid_next;
  logic             out_poison_next;
  logic [16:0]      credit_next;

  logic [15:0]      frame_len_eff;
  logic [16:0]      frame_len_ext;
  logic [16:0]      count_ext;
  logic [16:0]      count_inc;

  assign frame_len_eff = (frame_len == 16'd0) ? 16'd1 : frame_len;
  assign frame_len_ext = {1'b0, frame_len_eff};
  assign count_ext     = {1'b0, count_reg};
  assign count_inc     = count_ext + 17'd1;

  assign in_ready     = !out_valid_reg || out_ready;
  assign out_valid    = out_valid_reg;
  assign out_frame_acc= out_frame_acc_reg;
  assign out_tuser    = out_tuser_reg;
  assign out_last     = out_last_reg;
  assign out_poison   = out_poison_reg;
  assign credit_depth = credit_reg;

  always_comb begin
    acc_next            = acc_reg;
    count_next          = count_reg;
    poison_frame_next   = poison_frame_reg;
    out_frame_acc_next  = out_frame_acc_reg;
    out_tuser_next      = out_tuser_reg;
    out_last_next       = out_last_reg;
    out_valid_next      = out_valid_reg;
    out_poison_next     = out_poison_reg;
    credit_next         = (frame_len_ext > count_ext) ? frame_len_ext - count_ext : 17'd0;
    if (credit_next > 17'd65535) begin
      credit_next = 17'd65535;
    end

    if (out_valid_reg && out_ready) begin
      out_valid_next  = 1'b0;
      out_last_next   = 1'b0;
      out_poison_next = 1'b0;
    end

    if (in_valid && in_ready) begin
      logic [W_ACC-1:0] sample_value;
      logic [W_ACC-1:0] sum_value;
      logic             frame_done;
      logic [16:0]      credit_after_sample;

      sample_value = in_partial_acc;
      sum_value    = (count_reg == 16'd0) ? sample_value : (acc_reg + sample_value);

      frame_done = in_last;
      if (tree_type) begin
        frame_done = frame_done || (count_inc >= frame_len_ext);
      end

      count_next        = frame_done ? 16'd0 : count_inc[15:0];
      acc_next          = frame_done ? '0 : sum_value;
      poison_frame_next = frame_done ? 1'b0 : (poison_frame_reg || in_poison);
      credit_after_sample = frame_done ? frame_len_ext :
        ((frame_len_ext > count_inc) ? (frame_len_ext - count_inc) : 17'd0);
      credit_next       = (credit_after_sample > 17'd65535) ? 17'd65535 : credit_after_sample;
      out_tuser_next    = in_tuser;

      if (frame_done) begin
        out_frame_acc_next = sum_value;
        out_valid_next     = 1'b1;
        out_last_next      = 1'b1;
        out_poison_next    = poison_frame_reg || in_poison;
      end else begin
        out_last_next   = 1'b0;
      end
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      acc_reg           <= '0;
      count_reg         <= 16'd0;
      poison_frame_reg  <= 1'b0;
      out_frame_acc_reg <= '0;
      out_tuser_reg     <= '0;
      out_last_reg      <= 1'b0;
      out_valid_reg     <= 1'b0;
      out_poison_reg    <= 1'b0;
      credit_reg        <= frame_len_eff;
    end else begin
      acc_reg           <= acc_next;
      count_reg         <= count_next;
      poison_frame_reg  <= poison_frame_next;
      out_frame_acc_reg <= out_frame_acc_next;
      out_tuser_reg     <= out_tuser_next;
      out_last_reg      <= out_last_next;
      out_valid_reg     <= out_valid_next;
      out_poison_reg    <= out_poison_next;
      credit_reg        <= credit_next[15:0];
    end
  end

endmodule : ime_acc_tree

