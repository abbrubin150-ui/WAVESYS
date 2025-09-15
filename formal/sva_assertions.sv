// sva_assertions.sv
// Formal assertion templates for the IME datapath. Capture EXACT1, poison propagation,
// and BIST gating semantics as described in the freeze-pack verification guidance.

module ime_sva_assertions #(
  parameter int MODE_WIDTH   = 3,
  parameter int MODE_LSB     = 0,
  parameter int W_USER       = 8,
  parameter int W_ACC        = 32,
  parameter int CREDIT_WIDTH = 16
) (
  input  logic                       clk,
  input  logic                       rst_n,
  input  logic [W_USER-1:0]          s_axis_tuser,
  input  logic                       s_axis_tvalid,
  input  logic                       s_axis_tready,
  input  logic                       s_axis_tlast,
  input  logic                       m_axis_tvalid,
  input  logic                       m_axis_tready,
  input  logic                       m_axis_tlast,
  input  logic [W_ACC-1:0]           m_axis_tdata,
  input  logic                       poison_flag,
  input  logic [3:0]                 error_flags,
  input  logic [1:0]                 bist_status,
  input  logic [CREDIT_WIDTH-1:0]    credit_depth
);

  // Default clocking and reset context for assertions.
  default clocking cb @(posedge clk);
    default input #1step;
    default output #1step;
  endclocking

  default disable iff (!rst_n);

  localparam int MODE_MSB = MODE_LSB + MODE_WIDTH - 1;

  // ---------------------------------------------------------------------------
  // EXACT1 — ensure only a single mode bit is asserted per frame header.
  // Replace bit-slice constants once the CSR map is finalized.
  // ---------------------------------------------------------------------------
  property p_exact1_mode_select;
    (s_axis_tvalid && s_axis_tready && s_axis_tlast)
      |-> $onehot(s_axis_tuser[MODE_MSB:MODE_LSB]);
  endproperty

  assert property (p_exact1_mode_select)
    else $error("EXACT1 violation: multiple mode selects observed on tuser.");

  // ---------------------------------------------------------------------------
  // Poison propagation — once POISON is raised, downstream data must be benign.
  // ---------------------------------------------------------------------------
  property p_poison_zeroizes_output;
    poison_flag && m_axis_tvalid && m_axis_tready
      |-> (m_axis_tdata == '0);
  endproperty

  assert property (p_poison_zeroizes_output)
    else $error("Poison contract violation: non-zero output observed under poison.");

  // ---------------------------------------------------------------------------
  // BIST gating — while self-test is active, external traffic should be blocked.
  // Update bist_status encodings when the BIST controller spec is finalized.
  // ---------------------------------------------------------------------------
  localparam logic [1:0] BIST_IDLE    = 2'b00;
  localparam logic [1:0] BIST_RUNNING = 2'b01;

  property p_bist_blocks_stream;
    (bist_status == BIST_RUNNING) |-> !m_axis_tvalid;
  endproperty

  assert property (p_bist_blocks_stream)
    else $error("BIST gating violation: user traffic observed while BIST active.");

  // ---------------------------------------------------------------------------
  // Credit tracker sanity — credit counter should never underflow below zero.
  // ---------------------------------------------------------------------------
  property p_credit_never_wraps;
    (s_axis_tvalid && !s_axis_tready)
      |-> ##1 (credit_depth != {CREDIT_WIDTH{1'b1}});
  endproperty

  assert property (p_credit_never_wraps)
    else $error("Credit depth wrapped below zero; check flow-control implementation.");

  // ---------------------------------------------------------------------------
  // Coverage scaffolding — ensure poison and BIST events are observable.
  // ---------------------------------------------------------------------------
  cover property (@cb (poison_flag ##1 !poison_flag));
  cover property (@cb (bist_status == BIST_RUNNING ##1 bist_status != BIST_IDLE));

endmodule : ime_sva_assertions
