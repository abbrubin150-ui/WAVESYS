// ime_joint_framer.sv
// Joint probability framing unit for mutual-information mode, aligning p(x,y) with marginal buffers.
// Handles dual-port BRAM addressing, frame counters, and poison-aware bookkeeping.
// TODO: Implement joint/marginal buffering, alignment pipeline, and handshake to downstream stages.

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

  // TODO: Implement dual-port memory scheduling and frame alignment for MI computations.

endmodule : ime_joint_framer

