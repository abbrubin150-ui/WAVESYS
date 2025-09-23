// ime_joint_framer.sv
// Joint probability framing unit for mutual-information mode, aligning p(x,y) with marginal buffers.
// Handles dual-port BRAM addressing, frame counters, and poison-aware bookkeeping.
// Implements a basic framing pipeline with frame and stride counters, ensuring poison and LAST
// propagation toward the adaptive log2 stage during mutual-information mode smoke tests.

module ime_joint_framer #(
  parameter int W_P      = 16,
  parameter int W_LOG    = 16,
  parameter int W_ACC    = 32,
  parameter int LUT_SIZE = 256,
  parameter int PWL_SEG  = 2,
  parameter int K_MAX    = 4096
) (
  input  logic                   clk,
  input  logic                   rst_n,

  // Incoming joint and marginal probability streams
  input  logic                   in_valid,
  output logic                   in_ready,
  input  logic [W_P-1:0]         in_p_joint,
  input  logic [W_P-1:0]         in_p_marg_x,
  input  logic [W_P-1:0]         in_p_marg_y,
  input  logic                   in_last,
  input  logic                   in_poison,

  // Configuration inputs
  input  logic [15:0]            frame_len,
  input  logic [15:0]            frame_stride,
  input  logic [4:0]             mode_onehot,

  // Output toward log2 stage
  output logic                   out_valid,
  input  logic                   out_ready,
  output logic [W_P-1:0]         out_p_joint,
  output logic [W_P-1:0]         out_p_marg_x,
  output logic [W_P-1:0]         out_p_marg_y,
  output logic                   out_last,
  output logic                   out_poison
);

  function automatic logic mode_exact1(input logic [4:0] mode);
    logic [4:0] masked;
    masked = mode & (mode - 5'd1);
    return (mode != '0) && (masked == '0);
  endfunction

  logic                   stage_valid;
  logic [W_P-1:0]         joint_reg;
  logic [W_P-1:0]         marg_x_reg;
  logic [W_P-1:0]         marg_y_reg;
  logic                   last_reg;
  logic                   poison_reg;
  logic [15:0]            frame_index_reg;
  logic [15:0]            stride_index_reg;

  logic [15:0]            frame_len_eff;
  logic [15:0]            frame_stride_eff;

  assign frame_len_eff     = (frame_len == 16'd0) ? 16'd1 : frame_len;
  assign frame_stride_eff  = frame_stride;

  assign in_ready   = !stage_valid || (stage_valid && out_ready);
  assign out_valid  = stage_valid;
  assign out_p_joint= joint_reg;
  assign out_p_marg_x = marg_x_reg;
  assign out_p_marg_y = marg_y_reg;
  assign out_last   = last_reg;
  assign out_poison = poison_reg;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      stage_valid       <= 1'b0;
      joint_reg         <= '0;
      marg_x_reg        <= '0;
      marg_y_reg        <= '0;
      last_reg          <= 1'b0;
      poison_reg        <= 1'b0;
      frame_index_reg   <= 16'd0;
      stride_index_reg  <= 16'd0;
    end else begin
      if (in_valid && in_ready) begin
        logic [16:0] next_index;
        logic        frame_done;
        logic        mode_error;

        joint_reg        <= in_p_joint;
        marg_x_reg       <= in_p_marg_x;
        marg_y_reg       <= in_p_marg_y;
        mode_error       = (mode_onehot != '0) && !mode_exact1(mode_onehot);
        next_index       = {1'b0, frame_index_reg} + 17'd1;
        frame_done       = in_last || (next_index >= {1'b0, frame_len_eff});
        last_reg         <= frame_done;
        poison_reg       <= in_poison || mode_error;
        stage_valid      <= 1'b1;

        if (frame_done) begin
          frame_index_reg  <= 16'd0;
          stride_index_reg <= stride_index_reg + frame_stride_eff;
        end else begin
          frame_index_reg  <= next_index[15:0];
        end
      end

      if (stage_valid && out_ready) begin
        stage_valid <= 1'b0;
      end
    end
  end

endmodule : ime_joint_framer

