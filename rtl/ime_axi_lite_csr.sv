// ime_axi_lite_csr.sv
// Control/status register block accessible over AXI-Lite to configure the IME pipeline.
// Captures CSR map from the freeze-pack and distributes configuration plus collects status.
// Implements a minimal AXI-Lite slave with EXACT1 enforcement on mode fields and
// sticky mode_error reporting to honour fail-closed behaviour.

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

  localparam logic [1:0] RESP_OKAY  = 2'b00;
  localparam logic [1:0] RESP_SLVERR= 2'b10;

  localparam int unsigned ADDR_LSB = 2;
  localparam int unsigned ADDR_MSB = 7;

  localparam logic [ADDR_MSB-ADDR_LSB:0] ADDR_MODE         = 'h00;
  localparam logic [ADDR_MSB-ADDR_LSB:0] ADDR_TREE         = 'h01;
  localparam logic [ADDR_MSB-ADDR_LSB:0] ADDR_LUT_PWL      = 'h02;
  localparam logic [ADDR_MSB-ADDR_LSB:0] ADDR_CONST_TIME   = 'h03;
  localparam logic [ADDR_MSB-ADDR_LSB:0] ADDR_QP_FRAC      = 'h04;
  localparam logic [ADDR_MSB-ADDR_LSB:0] ADDR_QLOG_FRAC    = 'h05;
  localparam logic [ADDR_MSB-ADDR_LSB:0] ADDR_EPSILON_Q    = 'h06;
  localparam logic [ADDR_MSB-ADDR_LSB:0] ADDR_DELTA_THRESH = 'h07;
  localparam logic [ADDR_MSB-ADDR_LSB:0] ADDR_FRAME_LEN    = 'h08;
  localparam logic [ADDR_MSB-ADDR_LSB:0] ADDR_BIST_CTRL    = 'h09;
  localparam logic [ADDR_MSB-ADDR_LSB:0] ADDR_STATUS       = 'h0A;

  function automatic logic [4:0] sanitize_mode(input logic [4:0] mode_bits);
    logic [4:0] masked;
    masked = mode_bits & (mode_bits - 5'd1);
    return ((mode_bits != '0) && (masked == '0)) ? mode_bits : 5'b00001;
  endfunction

  function automatic logic exact1(input logic [4:0] mode_bits);
    logic [4:0] masked;
    masked = mode_bits & (mode_bits - 5'd1);
    return (mode_bits != '0) && (masked == '0);
  endfunction

  logic [4:0]   mode_reg;
  logic         tree_reg;
  logic [7:0]   lut_size_reg;
  logic [1:0]   pwl_segments_reg;
  logic [13:0]  const_time_reg;
  logic [11:0]  qp_frac_reg;
  logic [11:0]  qlog_frac_reg;
  logic [15:0]  epsilon_q_reg;
  logic [15:0]  delta_thresh_reg;
  logic [15:0]  frame_len_reg;
  logic [1:0]   bist_cmd_reg;
  logic [2:0]   vect_sel_reg;
  logic [7:0]   bist_tol_reg;
  logic         mode_error_reg;

  logic [ADDR_MSB-ADDR_LSB:0] awaddr_reg;
  logic [ADDR_MSB-ADDR_LSB:0] araddr_reg;

  logic write_selected;
  logic read_selected;

  assign mode_onehot       = mode_reg;
  assign tree_type         = tree_reg;
  assign lut_size_cfg      = lut_size_reg;
  assign pwl_segments_cfg  = pwl_segments_reg;
  assign const_time_cycles = const_time_reg;
  assign qp_frac           = qp_frac_reg;
  assign qlog_frac         = qlog_frac_reg;
  assign epsilon_q         = epsilon_q_reg;
  assign delta_thresh      = delta_thresh_reg;
  assign frame_len         = frame_len_reg;
  assign bist_cmd          = bist_cmd_reg;
  assign vect_sel          = vect_sel_reg;
  assign bist_tol          = bist_tol_reg;

  assign s_axi_awready = !s_axi_bvalid && s_axi_awvalid && s_axi_wvalid;
  assign s_axi_wready  = !s_axi_bvalid && s_axi_awvalid && s_axi_wvalid;
  assign s_axi_bresp   = RESP_OKAY;

  assign s_axi_arready = !s_axi_rvalid;
  assign s_axi_rresp   = RESP_OKAY;

  assign write_selected = s_axi_awvalid && s_axi_wvalid && s_axi_awready && s_axi_wready;
  assign read_selected  = s_axi_arvalid && s_axi_arready;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      mode_reg        <= 5'b00001;
      tree_reg        <= 1'b0;
      lut_size_reg    <= LUT_SIZE[7:0];
      pwl_segments_reg<= PWL_SEG[1:0];
      const_time_reg  <= 14'd0;
      qp_frac_reg     <= 12'd0;
      qlog_frac_reg   <= 12'd0;
      epsilon_q_reg   <= 16'd1;
      delta_thresh_reg<= 16'd0;
      frame_len_reg   <= 16'd1;
      bist_cmd_reg    <= 2'b00;
      vect_sel_reg    <= 3'd0;
      bist_tol_reg    <= 8'd0;
      mode_error_reg  <= 1'b0;
      awaddr_reg      <= '0;
      araddr_reg      <= '0;
      s_axi_bvalid    <= 1'b0;
      s_axi_rvalid    <= 1'b0;
      s_axi_rdata     <= '0;
    end else begin
      if (s_axi_awready && s_axi_awvalid) begin
        awaddr_reg <= s_axi_awaddr[ADDR_MSB:ADDR_LSB];
      end

      if (s_axi_arready && s_axi_arvalid) begin
        araddr_reg <= s_axi_araddr[ADDR_MSB:ADDR_LSB];
      end

      if (write_selected) begin
        case (s_axi_awaddr[ADDR_MSB:ADDR_LSB])
          ADDR_MODE: begin
            mode_reg       <= sanitize_mode(s_axi_wdata[4:0]);
            mode_error_reg <= !exact1(s_axi_wdata[4:0]);
          end
          ADDR_TREE: begin
            tree_reg <= s_axi_wdata[0];
          end
          ADDR_LUT_PWL: begin
            lut_size_reg     <= s_axi_wdata[15:8];
            pwl_segments_reg <= s_axi_wdata[1:0];
          end
          ADDR_CONST_TIME: begin
            const_time_reg <= s_axi_wdata[13:0];
          end
          ADDR_QP_FRAC: begin
            qp_frac_reg <= s_axi_wdata[11:0];
          end
          ADDR_QLOG_FRAC: begin
            qlog_frac_reg <= s_axi_wdata[11:0];
          end
          ADDR_EPSILON_Q: begin
            epsilon_q_reg <= s_axi_wdata[15:0];
          end
          ADDR_DELTA_THRESH: begin
            delta_thresh_reg <= s_axi_wdata[15:0];
          end
          ADDR_FRAME_LEN: begin
            frame_len_reg <= s_axi_wdata[15:0];
          end
          ADDR_BIST_CTRL: begin
            bist_cmd_reg <= s_axi_wdata[1:0];
            vect_sel_reg <= s_axi_wdata[4:2];
            bist_tol_reg <= s_axi_wdata[15:8];
          end
          default: begin
          end
        endcase
      end

      if (write_selected) begin
        s_axi_bvalid <= 1'b1;
      end else if (s_axi_bvalid && s_axi_bready) begin
        s_axi_bvalid <= 1'b0;
      end

      if (read_selected) begin
        case (s_axi_araddr[ADDR_MSB:ADDR_LSB])
          ADDR_MODE:         s_axi_rdata <= {27'd0, mode_reg};
          ADDR_TREE:         s_axi_rdata <= {31'd0, tree_reg};
          ADDR_LUT_PWL:      s_axi_rdata <= {16'd0, lut_size_reg, 6'd0, pwl_segments_reg};
          ADDR_CONST_TIME:   s_axi_rdata <= {18'd0, const_time_reg};
          ADDR_QP_FRAC:      s_axi_rdata <= {20'd0, qp_frac_reg};
          ADDR_QLOG_FRAC:    s_axi_rdata <= {20'd0, qlog_frac_reg};
          ADDR_EPSILON_Q:    s_axi_rdata <= {16'd0, epsilon_q_reg};
          ADDR_DELTA_THRESH: s_axi_rdata <= {16'd0, delta_thresh_reg};
          ADDR_FRAME_LEN:    s_axi_rdata <= {16'd0, frame_len_reg};
          ADDR_BIST_CTRL:    s_axi_rdata <= {16'd0, bist_tol_reg, 3'd0, vect_sel_reg, bist_cmd_reg};
          ADDR_STATUS: begin
            s_axi_rdata <= {credit_depth,
                             4'd0,
                             error_flags,
                             poison_flag,
                             bist_status,
                             mode_error_reg,
                             4'd0};
          end
          default:          s_axi_rdata <= 32'hDEAD_BEEF;
        endcase
        s_axi_rvalid <= 1'b1;
      end else if (s_axi_rvalid && s_axi_rready) begin
        s_axi_rvalid <= 1'b0;
      end
    end
  end

endmodule : ime_axi_lite_csr

