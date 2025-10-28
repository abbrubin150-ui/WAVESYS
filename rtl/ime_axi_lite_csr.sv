// ime_axi_lite_csr.sv
// Control/status register block accessible over AXI-Lite to configure the IME pipeline.
// Captures CSR map from the freeze-pack and distributes configuration plus collects status.
// Implements AXI-Lite slave with register decoding, EXACT1 mode enforcement, and status capture.

module ime_axi_lite_csr #(
  parameter int W_P      = 16,
  parameter int W_LOG    = 16,
  parameter int W_ACC    = 32,
  parameter int LUT_SIZE = 256,
  parameter int PWL_SEG  = 2,
  parameter int K_MAX    = 4096
) (
  input  logic         clk,
  input  logic         rst_n,

  // AXI-Lite slave interface
  input  logic [15:0]  s_axi_awaddr,
  input  logic         s_axi_awvalid,
  output logic         s_axi_awready,
  input  logic [31:0]  s_axi_wdata,
  input  logic [3:0]   s_axi_wstrb,
  input  logic         s_axi_wvalid,
  output logic         s_axi_wready,
  output logic [1:0]   s_axi_bresp,
  output logic         s_axi_bvalid,
  input  logic         s_axi_bready,
  input  logic [15:0]  s_axi_araddr,
  input  logic         s_axi_arvalid,
  output logic         s_axi_arready,
  output logic [31:0]  s_axi_rdata,
  output logic [1:0]   s_axi_rresp,
  output logic         s_axi_rvalid,
  input  logic         s_axi_rready,

  // Configuration outputs
  output logic [4:0]   mode_onehot,
  output logic         tree_type,
  output logic [7:0]   lut_size_cfg,
  output logic [1:0]   pwl_segments_cfg,
  output logic [13:0]  const_time_cycles,
  output logic [11:0]  qp_frac,
  output logic [11:0]  qlog_frac,
  output logic [15:0]  epsilon_q,
  output logic [15:0]  delta_thresh,
  output logic [15:0]  frame_len,
  output logic [1:0]   bist_cmd,
  output logic [2:0]   vect_sel,
  output logic [7:0]   bist_tol,

  // Status inputs
  input  logic [15:0]  credit_depth,
  input  logic [3:0]   error_flags,
  input  logic         poison_flag,
  input  logic [1:0]   bist_status
);

  // =========================================================================
  // Register addresses
  // =========================================================================
  localparam logic [15:0] ADDR_CFG0      = 16'h0000;
  localparam logic [15:0] ADDR_CFG1      = 16'h0004;
  localparam logic [15:0] ADDR_CFG2      = 16'h0008;
  localparam logic [15:0] ADDR_CFG3      = 16'h000C;
  localparam logic [15:0] ADDR_STAT      = 16'h0010;
  localparam logic [15:0] ADDR_BIST_CTRL = 16'h0014;

  // =========================================================================
  // Configuration registers
  // =========================================================================
  logic [4:0]   cfg0_mode_onehot;
  logic         cfg0_tree_type;
  logic [7:0]   cfg0_lut_size;
  logic [1:0]   cfg0_pwl_segments;
  logic [13:0]  cfg0_const_time_cycles;

  logic [11:0]  cfg1_qp_frac;
  logic [11:0]  cfg1_qlog_frac;

  logic [15:0]  cfg2_epsilon_q;
  logic [15:0]  cfg2_delta_thresh;

  logic [15:0]  cfg3_frame_len;

  logic [3:0]   stat_error_flags;
  logic         stat_poison;
  logic [1:0]   stat_bist_status;

  logic [2:0]   bist_ctrl_vect_sel;
  logic [7:0]   bist_ctrl_tol;
  logic [1:0]   bist_cmd_reg;

  // =========================================================================
  // Output assignments
  // =========================================================================
  assign mode_onehot        = cfg0_mode_onehot;
  assign tree_type          = cfg0_tree_type;
  assign lut_size_cfg       = cfg0_lut_size;
  assign pwl_segments_cfg   = cfg0_pwl_segments;
  assign const_time_cycles  = cfg0_const_time_cycles;
  assign qp_frac            = cfg1_qp_frac;
  assign qlog_frac          = cfg1_qlog_frac;
  assign epsilon_q          = cfg2_epsilon_q;
  assign delta_thresh       = cfg2_delta_thresh;
  assign frame_len          = cfg3_frame_len;
  assign vect_sel           = bist_ctrl_vect_sel;
  assign bist_tol           = bist_ctrl_tol;
  assign bist_cmd           = bist_cmd_reg;

  // =========================================================================
  // EXACT1 enforcement: check mode_onehot has exactly one bit set
  // =========================================================================
  function automatic logic check_exact1(input logic [4:0] mode);
    logic [4:0] masked;
    masked = mode & (mode - 5'd1);
    return (mode != 5'b00000) && (masked == 5'b00000);
  endfunction

  // =========================================================================
  // AXI-Lite Write State Machine
  // =========================================================================
  typedef enum logic [1:0] {
    WR_IDLE   = 2'b00,
    WR_DATA   = 2'b01,
    WR_RESP   = 2'b10
  } wr_state_t;

  wr_state_t wr_state_reg, wr_state_next;
  logic [15:0] wr_addr_reg, wr_addr_next;
  logic [31:0] wr_data_reg, wr_data_next;
  logic [1:0]  wr_resp_reg, wr_resp_next;

  // Write ready signals
  assign s_axi_awready = (wr_state_reg == WR_IDLE);
  assign s_axi_wready  = (wr_state_reg == WR_DATA);
  assign s_axi_bresp   = wr_resp_reg;
  assign s_axi_bvalid  = (wr_state_reg == WR_RESP);

  // =========================================================================
  // AXI-Lite Read State Machine
  // =========================================================================
  typedef enum logic [1:0] {
    RD_IDLE = 2'b00,
    RD_DATA = 2'b01
  } rd_state_t;

  rd_state_t rd_state_reg, rd_state_next;
  logic [15:0] rd_addr_reg, rd_addr_next;
  logic [31:0] rd_data_reg, rd_data_next;
  logic [1:0]  rd_resp_reg, rd_resp_next;

  // Read ready signals
  assign s_axi_arready = (rd_state_reg == RD_IDLE);
  assign s_axi_rdata   = rd_data_reg;
  assign s_axi_rresp   = rd_resp_reg;
  assign s_axi_rvalid  = (rd_state_reg == RD_DATA);

  // =========================================================================
  // Write State Machine Logic
  // =========================================================================
  always_comb begin
    wr_state_next = wr_state_reg;
    wr_addr_next  = wr_addr_reg;
    wr_data_next  = wr_data_reg;
    wr_resp_next  = wr_resp_reg;

    case (wr_state_reg)
      WR_IDLE: begin
        if (s_axi_awvalid) begin
          wr_addr_next  = s_axi_awaddr;
          wr_state_next = WR_DATA;
        end
      end

      WR_DATA: begin
        if (s_axi_wvalid) begin
          wr_data_next  = s_axi_wdata;
          wr_resp_next  = 2'b00; // OKAY
          wr_state_next = WR_RESP;
        end
      end

      WR_RESP: begin
        if (s_axi_bready) begin
          wr_state_next = WR_IDLE;
        end
      end

      default: begin
        wr_state_next = WR_IDLE;
      end
    endcase
  end

  // =========================================================================
  // Read State Machine Logic
  // =========================================================================
  always_comb begin
    rd_state_next = rd_state_reg;
    rd_addr_next  = rd_addr_reg;
    rd_data_next  = rd_data_reg;
    rd_resp_next  = rd_resp_reg;

    case (rd_state_reg)
      RD_IDLE: begin
        if (s_axi_arvalid) begin
          rd_addr_next  = s_axi_araddr;
          rd_resp_next  = 2'b00; // OKAY
          rd_state_next = RD_DATA;
        end
      end

      RD_DATA: begin
        if (s_axi_rready) begin
          rd_state_next = RD_IDLE;
        end
      end

      default: begin
        rd_state_next = RD_IDLE;
      end
    endcase
  end

  // =========================================================================
  // Register File Update and Read Logic
  // =========================================================================
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      // Write channel
      wr_state_reg <= WR_IDLE;
      wr_addr_reg  <= '0;
      wr_data_reg  <= '0;
      wr_resp_reg  <= 2'b00;

      // Read channel
      rd_state_reg <= RD_IDLE;
      rd_addr_reg  <= '0;
      rd_data_reg  <= '0;
      rd_resp_reg  <= 2'b00;

      // Configuration registers with reset values from spec
      cfg0_mode_onehot      <= 5'b00001;  // Default: Entropy mode
      cfg0_tree_type        <= 1'b0;
      cfg0_lut_size         <= 8'd256;
      cfg0_pwl_segments     <= 2'b10;
      cfg0_const_time_cycles<= 14'h0;

      cfg1_qp_frac          <= 12'd15;
      cfg1_qlog_frac        <= 12'd14;

      cfg2_epsilon_q        <= 16'h0001;
      cfg2_delta_thresh     <= 16'h0001;

      cfg3_frame_len        <= 16'h1000;

      stat_error_flags      <= 4'h0;
      stat_poison           <= 1'b0;
      stat_bist_status      <= 2'b00;

      bist_ctrl_vect_sel    <= 3'b000;
      bist_ctrl_tol         <= 8'h01;
      bist_cmd_reg          <= 2'b00;

    end else begin
      // =====================================================================
      // Write Channel State Machine
      // =====================================================================
      wr_state_reg <= wr_state_next;
      wr_addr_reg  <= wr_addr_next;
      wr_data_reg  <= wr_data_next;
      wr_resp_reg  <= wr_resp_next;

      // =====================================================================
      // Register writes when in WR_RESP state
      // =====================================================================
      if (wr_state_reg == WR_DATA && s_axi_wvalid) begin
        case (wr_addr_reg)
          ADDR_CFG0: begin
            logic [4:0] mode_written;
            mode_written = wr_data_reg[4:0];
            // EXACT1 enforcement: only write if exactly one bit set
            if (check_exact1(mode_written)) begin
              cfg0_mode_onehot <= mode_written;
            end
            cfg0_tree_type         <= wr_data_reg[5];
            cfg0_lut_size          <= wr_data_reg[15:8];
            cfg0_pwl_segments      <= wr_data_reg[17:16];
            cfg0_const_time_cycles <= wr_data_reg[31:18];
          end

          ADDR_CFG1: begin
            cfg1_qp_frac   <= wr_data_reg[11:0];
            cfg1_qlog_frac <= wr_data_reg[23:12];
          end

          ADDR_CFG2: begin
            cfg2_epsilon_q    <= wr_data_reg[15:0];
            cfg2_delta_thresh <= wr_data_reg[31:16];
          end

          ADDR_CFG3: begin
            // [15:0] is RO (credit_depth), only write [31:16]
            cfg3_frame_len <= wr_data_reg[31:16];
          end

          ADDR_STAT: begin
            // W1C for error_flags: write 1 to clear
            if (wr_data_reg[0]) stat_error_flags[0] <= 1'b0;
            if (wr_data_reg[1]) stat_error_flags[1] <= 1'b0;
            if (wr_data_reg[2]) stat_error_flags[2] <= 1'b0;
            if (wr_data_reg[3]) stat_error_flags[3] <= 1'b0;
            // Poison and BIST_STATUS are read-only, no write
          end

          ADDR_BIST_CTRL: begin
            bist_cmd_reg        <= wr_data_reg[1:0];  // WO, pulse
            bist_ctrl_vect_sel  <= wr_data_reg[4:2];
            bist_ctrl_tol       <= wr_data_reg[15:8];
          end

          default: begin
            // Invalid address, do nothing
          end
        endcase
      end

      // =====================================================================
      // Read Channel State Machine
      // =====================================================================
      rd_state_reg <= rd_state_next;
      rd_addr_reg  <= rd_addr_next;
      rd_resp_reg  <= rd_resp_next;

      // =====================================================================
      // Register reads when entering RD_DATA state
      // =====================================================================
      if (rd_state_reg == RD_IDLE && s_axi_arvalid) begin
        case (s_axi_araddr)
          ADDR_CFG0: begin
            rd_data_next = {cfg0_const_time_cycles, cfg0_pwl_segments,
                            6'b0, cfg0_lut_size, cfg0_tree_type, cfg0_mode_onehot};
          end

          ADDR_CFG1: begin
            rd_data_next = {8'b0, cfg1_qlog_frac, cfg1_qp_frac};
          end

          ADDR_CFG2: begin
            rd_data_next = {cfg2_delta_thresh, cfg2_epsilon_q};
          end

          ADDR_CFG3: begin
            rd_data_next = {cfg3_frame_len, credit_depth};
          end

          ADDR_STAT: begin
            rd_data_next = {25'b0, stat_bist_status, stat_poison, stat_error_flags};
          end

          ADDR_BIST_CTRL: begin
            rd_data_next = {16'b0, bist_ctrl_tol, 3'b0, bist_ctrl_vect_sel, 2'b0};
          end

          default: begin
            rd_data_next = 32'hDEADBEEF; // Invalid address marker
          end
        endcase
        rd_data_reg <= rd_data_next;
      end

      // =====================================================================
      // Status capture from pipeline
      // =====================================================================
      // Latch error_flags (sticky, W1C)
      stat_error_flags <= stat_error_flags | error_flags;
      stat_poison      <= poison_flag;
      stat_bist_status <= bist_status;

      // Clear bist_cmd after one cycle (pulse)
      if (bist_cmd_reg != 2'b00) begin
        bist_cmd_reg <= 2'b00;
      end
    end
  end

endmodule : ime_axi_lite_csr
