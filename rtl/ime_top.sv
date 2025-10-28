// ime_top.sv
// Top-level wrapper for the Information Metrics Engine (IME) pipeline.
// Exposes AXI-Lite control plane and AXI-Stream data plane interfaces per the freeze-pack spec.
// Integrates CSR, BIST, stream interface, adaptive log2, core operation, and accumulator blocks.

module ime_top #(
  parameter int W_P      = 16,
  parameter int W_LOG    = 16,
  parameter int W_ACC    = 32,
  parameter int LUT_SIZE = 256,
  parameter int PWL_SEG  = 2,
  parameter int K_MAX    = 4096
) (
  input  logic                       clk,
  input  logic                       rst_n,

  // AXI-Lite control plane (slave interface)
  input  logic [15:0]                s_axi_awaddr,
  input  logic                       s_axi_awvalid,
  output logic                       s_axi_awready,
  input  logic [31:0]                s_axi_wdata,
  input  logic [3:0]                 s_axi_wstrb,
  input  logic                       s_axi_wvalid,
  output logic                       s_axi_wready,
  output logic [1:0]                 s_axi_bresp,
  output logic                       s_axi_bvalid,
  input  logic                       s_axi_bready,
  input  logic [15:0]                s_axi_araddr,
  input  logic                       s_axi_arvalid,
  output logic                       s_axi_arready,
  output logic [31:0]                s_axi_rdata,
  output logic [1:0]                 s_axi_rresp,
  output logic                       s_axi_rvalid,
  input  logic                       s_axi_rready,

  // AXI-Stream style data input
  input  logic [W_P*2+W_LOG-1:0]     s_axis_tdata,
  input  logic [7:0]                 s_axis_tuser,
  input  logic                       s_axis_tvalid,
  output logic                       s_axis_tready,
  input  logic                       s_axis_tlast,

  // AXI-Stream style data output
  output logic [W_ACC-1:0]           m_axis_tdata,
  output logic [7:0]                 m_axis_tuser,
  output logic                       m_axis_tvalid,
  input  logic                       m_axis_tready,
  output logic                       m_axis_tlast,

  // Status and observability
  output logic [3:0]                 error_flags,
  output logic                       poison_flag,
  output logic [1:0]                 bist_status,
  output logic [15:0]                credit_depth
);

  // =========================================================================
  // Internal signals from CSR to pipeline configuration
  // =========================================================================
  logic [4:0]   cfg_mode_onehot;
  logic         cfg_tree_type;
  logic [7:0]   cfg_lut_size;
  logic [1:0]   cfg_pwl_segments;
  logic [13:0]  cfg_const_time_cycles;
  logic [11:0]  cfg_qp_frac;
  logic [11:0]  cfg_qlog_frac;
  logic [15:0]  cfg_epsilon_q;
  logic [15:0]  cfg_delta_thresh;
  logic [15:0]  cfg_frame_len;
  logic [1:0]   cfg_bist_cmd;
  logic [2:0]   cfg_vect_sel;
  logic [7:0]   cfg_bist_tol;

  // =========================================================================
  // BIST stimulus and control signals
  // =========================================================================
  logic                       bist_active;
  logic [W_P*2+W_LOG-1:0]     bist_tdata;
  logic [7:0]                 bist_tuser;
  logic                       bist_tvalid;
  logic                       bist_tready;
  logic                       bist_tlast;
  logic                       bist_poison_inject;

  // =========================================================================
  // Stream interface MUX: select between normal input and BIST
  // =========================================================================
  logic [W_P*2+W_LOG-1:0]     stream_in_tdata;
  logic [7:0]                 stream_in_tuser;
  logic                       stream_in_tvalid;
  logic                       stream_in_tready;
  logic                       stream_in_tlast;

  assign stream_in_tdata  = bist_active ? bist_tdata  : s_axis_tdata;
  assign stream_in_tuser  = bist_active ? bist_tuser  : s_axis_tuser;
  assign stream_in_tvalid = bist_active ? bist_tvalid : s_axis_tvalid;
  assign stream_in_tlast  = bist_active ? bist_tlast  : s_axis_tlast;

  assign s_axis_tready    = bist_active ? 1'b0        : stream_in_tready;
  assign bist_tready      = bist_active ? stream_in_tready : 1'b0;

  // =========================================================================
  // Pipeline stage signals
  // =========================================================================

  // Stream IF → Log2 Adapt
  logic               s0_valid;
  logic               s0_ready;
  logic [W_P-1:0]     s0_prob_p;
  logic [W_P-1:0]     s0_prob_q;
  logic [W_LOG-1:0]   s0_score;
  logic [7:0]         s0_tuser;
  logic               s0_last;
  logic               s0_poison;
  logic               s0_frame_start;
  logic               s0_frame_end;

  // Log2 Adapt → CoreOp
  logic               s1_valid;
  logic               s1_ready;
  logic [W_LOG-1:0]   s1_log_p;
  logic [W_LOG-1:0]   s1_log_q;
  logic [W_LOG-1:0]   s1_log_score;
  logic [W_P-1:0]     s1_prob_p;
  logic [W_P-1:0]     s1_prob_q;
  logic [7:0]         s1_tuser;
  logic               s1_last;
  logic               s1_use_pwl;
  logic               s1_poison;

  // CoreOp → Accumulator
  logic               s2_valid;
  logic               s2_ready;
  logic [W_ACC-1:0]   s2_partial_acc;
  logic [7:0]         s2_tuser;
  logic               s2_last;
  logic               s2_poison;

  // Accumulator → Output
  logic               s3_valid;
  logic               s3_ready;
  logic [W_ACC-1:0]   s3_frame_acc;
  logic [7:0]         s3_tuser;
  logic               s3_last;
  logic               s3_poison;

  // =========================================================================
  // Clock gating enables from CoreOp
  // =========================================================================
  logic cen_entropy;
  logic cen_cross_entropy;
  logic cen_kl;
  logic cen_mi;
  logic cen_fisher;

  // =========================================================================
  // Status signals
  // =========================================================================
  logic [15:0] status_credit_depth;
  logic [3:0]  status_error_flags;
  logic        status_poison_flag;
  logic [1:0]  status_bist_status;

  assign credit_depth  = status_credit_depth;
  assign error_flags   = status_error_flags;
  assign poison_flag   = status_poison_flag;
  assign bist_status   = status_bist_status;

  // TODO: error_flags accumulation from pipeline stages
  assign status_error_flags = 4'h0;
  assign status_poison_flag = s3_poison;

  // =========================================================================
  // Output assignment
  // =========================================================================
  assign m_axis_tdata  = s3_frame_acc;
  assign m_axis_tuser  = s3_tuser;
  assign m_axis_tvalid = s3_valid;
  assign m_axis_tlast  = s3_last;
  assign s3_ready      = m_axis_tready;

  // =========================================================================
  // Module instantiations
  // =========================================================================

  // -------------------------------------------------------------------------
  // CSR Block: AXI-Lite slave for control/status registers
  // -------------------------------------------------------------------------
  ime_axi_lite_csr #(
    .W_P      (W_P),
    .W_LOG    (W_LOG),
    .W_ACC    (W_ACC),
    .LUT_SIZE (LUT_SIZE),
    .PWL_SEG  (PWL_SEG),
    .K_MAX    (K_MAX)
  ) u_csr (
    .clk                (clk),
    .rst_n              (rst_n),
    // AXI-Lite slave
    .s_axi_awaddr       (s_axi_awaddr),
    .s_axi_awvalid      (s_axi_awvalid),
    .s_axi_awready      (s_axi_awready),
    .s_axi_wdata        (s_axi_wdata),
    .s_axi_wstrb        (s_axi_wstrb),
    .s_axi_wvalid       (s_axi_wvalid),
    .s_axi_wready       (s_axi_wready),
    .s_axi_bresp        (s_axi_bresp),
    .s_axi_bvalid       (s_axi_bvalid),
    .s_axi_bready       (s_axi_bready),
    .s_axi_araddr       (s_axi_araddr),
    .s_axi_arvalid      (s_axi_arvalid),
    .s_axi_arready      (s_axi_arready),
    .s_axi_rdata        (s_axi_rdata),
    .s_axi_rresp        (s_axi_rresp),
    .s_axi_rvalid       (s_axi_rvalid),
    .s_axi_rready       (s_axi_rready),
    // Configuration outputs
    .mode_onehot        (cfg_mode_onehot),
    .tree_type          (cfg_tree_type),
    .lut_size_cfg       (cfg_lut_size),
    .pwl_segments_cfg   (cfg_pwl_segments),
    .const_time_cycles  (cfg_const_time_cycles),
    .qp_frac            (cfg_qp_frac),
    .qlog_frac          (cfg_qlog_frac),
    .epsilon_q          (cfg_epsilon_q),
    .delta_thresh       (cfg_delta_thresh),
    .frame_len          (cfg_frame_len),
    .bist_cmd           (cfg_bist_cmd),
    .vect_sel           (cfg_vect_sel),
    .bist_tol           (cfg_bist_tol),
    // Status inputs
    .credit_depth       (status_credit_depth),
    .error_flags        (status_error_flags),
    .poison_flag        (status_poison_flag),
    .bist_status        (status_bist_status)
  );

  // -------------------------------------------------------------------------
  // BIST: Built-in self-test controller
  // -------------------------------------------------------------------------
  ime_bist #(
    .W_P      (W_P),
    .W_LOG    (W_LOG),
    .W_ACC    (W_ACC),
    .LUT_SIZE (LUT_SIZE),
    .PWL_SEG  (PWL_SEG),
    .K_MAX    (K_MAX)
  ) u_bist (
    .clk            (clk),
    .rst_n          (rst_n),
    // Control from CSR
    .bist_cmd       (cfg_bist_cmd),
    .vect_sel       (cfg_vect_sel),
    .tol            (cfg_bist_tol),
    .frame_len      (cfg_frame_len),
    // Stimulus output
    .bist_active    (bist_active),
    .bist_tdata     (bist_tdata),
    .bist_tuser     (bist_tuser),
    .bist_tvalid    (bist_tvalid),
    .bist_tready    (bist_tready),
    .bist_tlast     (bist_tlast),
    // Observation from accumulator
    .obs_acc        (s3_frame_acc),
    .obs_tuser      (s3_tuser),
    .obs_valid      (s3_valid),
    .obs_last       (s3_last),
    // Status back to CSR
    .bist_status    (status_bist_status),
    .poison_inject  (bist_poison_inject)
  );

  // -------------------------------------------------------------------------
  // Stream Interface: Stage S0 - Framing and epsilon floor
  // -------------------------------------------------------------------------
  ime_stream_if #(
    .W_P      (W_P),
    .W_LOG    (W_LOG),
    .W_ACC    (W_ACC),
    .LUT_SIZE (LUT_SIZE),
    .PWL_SEG  (PWL_SEG),
    .K_MAX    (K_MAX)
  ) u_stream_if (
    .clk                (clk),
    .rst_n              (rst_n),
    // AXI-Stream input (muxed with BIST)
    .s_axis_tdata       (stream_in_tdata),
    .s_axis_tuser       (stream_in_tuser),
    .s_axis_tvalid      (stream_in_tvalid),
    .s_axis_tready      (stream_in_tready),
    .s_axis_tlast       (stream_in_tlast),
    // Downstream handshake
    .out_valid          (s0_valid),
    .out_ready          (s0_ready),
    .out_prob_p         (s0_prob_p),
    .out_prob_q         (s0_prob_q),
    .out_score          (s0_score),
    .out_tuser          (s0_tuser),
    .out_last           (s0_last),
    .out_poison         (s0_poison),
    // Configuration
    .frame_len          (cfg_frame_len),
    .epsilon_q          (cfg_epsilon_q),
    .const_time_cycles  (cfg_const_time_cycles),
    // Flow control
    .frame_start        (s0_frame_start),
    .frame_end          (s0_frame_end),
    .poison_inject      (bist_poison_inject)
  );

  // -------------------------------------------------------------------------
  // Adaptive Log2: Stages S1-S3 - LZC, LUT, PWL
  // -------------------------------------------------------------------------
  ime_log2_adapt #(
    .W_P      (W_P),
    .W_LOG    (W_LOG),
    .W_ACC    (W_ACC),
    .LUT_SIZE (LUT_SIZE),
    .PWL_SEG  (PWL_SEG),
    .K_MAX    (K_MAX)
  ) u_log2_adapt (
    .clk                (clk),
    .rst_n              (rst_n),
    // Input handshake
    .in_valid           (s0_valid),
    .in_ready           (s0_ready),
    .in_prob_p          (s0_prob_p),
    .in_prob_q          (s0_prob_q),
    .in_score           (s0_score),
    .in_tuser           (s0_tuser),
    .in_last            (s0_last),
    .in_poison          (s0_poison),
    // Configuration
    .lut_size_cfg       (cfg_lut_size),
    .pwl_segments_cfg   (cfg_pwl_segments),
    .delta_thresh       (cfg_delta_thresh),
    .epsilon_q          (cfg_epsilon_q),
    // Output handshake
    .out_valid          (s1_valid),
    .out_ready          (s1_ready),
    .out_log_p          (s1_log_p),
    .out_log_q          (s1_log_q),
    .out_log_score      (s1_log_score),
    .out_prob_p         (s1_prob_p),
    .out_prob_q         (s1_prob_q),
    .out_tuser          (s1_tuser),
    .out_last           (s1_last),
    .out_use_pwl        (s1_use_pwl),
    .out_poison         (s1_poison)
  );

  // -------------------------------------------------------------------------
  // Core Operation: Stage S4 - Entropy/CE/KL/MI/Fisher
  // -------------------------------------------------------------------------
  ime_coreop #(
    .W_P      (W_P),
    .W_LOG    (W_LOG),
    .W_ACC    (W_ACC),
    .LUT_SIZE (LUT_SIZE),
    .PWL_SEG  (PWL_SEG),
    .K_MAX    (K_MAX)
  ) u_coreop (
    .clk                (clk),
    .rst_n              (rst_n),
    // Input handshake
    .in_valid           (s1_valid),
    .in_ready           (s1_ready),
    .in_log_p           (s1_log_p),
    .in_log_q           (s1_log_q),
    .in_log_score       (s1_log_score),
    .in_prob_p          (s1_prob_p),
    .in_prob_q          (s1_prob_q),
    .in_tuser           (s1_tuser),
    .in_last            (s1_last),
    .in_use_pwl         (s1_use_pwl),
    .in_poison          (s1_poison),
    // Configuration
    .mode_onehot        (cfg_mode_onehot),
    .const_time_cycles  (cfg_const_time_cycles),
    // Gating outputs
    .cen_entropy        (cen_entropy),
    .cen_cross_entropy  (cen_cross_entropy),
    .cen_kl             (cen_kl),
    .cen_mi             (cen_mi),
    .cen_fisher         (cen_fisher),
    // Output handshake
    .out_valid          (s2_valid),
    .out_ready          (s2_ready),
    .out_partial_acc    (s2_partial_acc),
    .out_tuser          (s2_tuser),
    .out_last           (s2_last),
    .out_poison         (s2_poison)
  );

  // -------------------------------------------------------------------------
  // Accumulator Tree: Stage S5 - Sequential or Kogge-Stone
  // -------------------------------------------------------------------------
  ime_acc_tree #(
    .W_P      (W_P),
    .W_LOG    (W_LOG),
    .W_ACC    (W_ACC),
    .LUT_SIZE (LUT_SIZE),
    .PWL_SEG  (PWL_SEG),
    .K_MAX    (K_MAX)
  ) u_acc_tree (
    .clk            (clk),
    .rst_n          (rst_n),
    // Input handshake
    .in_valid       (s2_valid),
    .in_ready       (s2_ready),
    .in_partial_acc (s2_partial_acc),
    .in_tuser       (s2_tuser),
    .in_last        (s2_last),
    .in_poison      (s2_poison),
    // Configuration
    .tree_type      (cfg_tree_type),
    .frame_len      (cfg_frame_len),
    // Output handshake
    .out_valid      (s3_valid),
    .out_ready      (s3_ready),
    .out_frame_acc  (s3_frame_acc),
    .out_tuser      (s3_tuser),
    .out_last       (s3_last),
    .out_poison     (s3_poison),
    // Status
    .credit_depth   (status_credit_depth)
  );

endmodule : ime_top

