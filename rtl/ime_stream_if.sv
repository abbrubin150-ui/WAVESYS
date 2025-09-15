// ime_stream_if.sv
// Front-end stream interface handling framing, epsilon floor, and poison propagation for the IME pipeline.
// Accepts AXI-Stream style traffic, enforces frame boundaries, and forwards normalized samples downstream.
// TODO: Implement buffering, credit tracking, and epsilon floor logic as described in the specification.

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

  // TODO: Add counters, frame state machine, and epsilon floor datapath.

endmodule : ime_stream_if

