// tb_ime_top.sv
// Top-level UVM testbench wrapper for the Information Metrics Engine (IME).
// Provides clock/reset stimulus, DUT instantiation, and hooks for the UVM runtime.

`timescale 1ns/1ps

module tb_ime_top;

  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import ime_uvm_pkg::*;

  // ---------------------------------------------------------------------------
  // Clock and reset generation
  // ---------------------------------------------------------------------------
  logic clk;
  logic rst_n;

  localparam time CLK_PERIOD = 10ns;

  initial begin
    clk = 1'b0;
    forever #(CLK_PERIOD/2) clk = ~clk;
  end

  initial begin
    rst_n = 1'b0;
    repeat (5) @(posedge clk);
    rst_n = 1'b1;
  end

  // ---------------------------------------------------------------------------
  // AXI-Lite control plane stimulus placeholders
  // ---------------------------------------------------------------------------
  logic [15:0] s_axi_awaddr;
  logic        s_axi_awvalid;
  logic        s_axi_awready;
  logic [31:0] s_axi_wdata;
  logic [3:0]  s_axi_wstrb;
  logic        s_axi_wvalid;
  logic        s_axi_wready;
  logic [1:0]  s_axi_bresp;
  logic        s_axi_bvalid;
  logic        s_axi_bready;
  logic [15:0] s_axi_araddr;
  logic        s_axi_arvalid;
  logic        s_axi_arready;
  logic [31:0] s_axi_rdata;
  logic [1:0]  s_axi_rresp;
  logic        s_axi_rvalid;
  logic        s_axi_rready;

  // ---------------------------------------------------------------------------
  // AXI-Stream style sample plane stimulus placeholders
  // ---------------------------------------------------------------------------
  localparam int W_P      = 16;
  localparam int W_LOG    = 16;
  localparam int W_ACC    = 32;

  logic [W_P*2+W_LOG-1:0] s_axis_tdata;
  logic [7:0]             s_axis_tuser;
  logic                   s_axis_tvalid;
  logic                   s_axis_tready;
  logic                   s_axis_tlast;

  logic [W_ACC-1:0]       m_axis_tdata;
  logic [7:0]             m_axis_tuser;
  logic                   m_axis_tvalid;
  logic                   m_axis_tready;
  logic                   m_axis_tlast;

  logic [3:0]             error_flags;
  logic                   poison_flag;
  logic [1:0]             bist_status;
  logic [15:0]            credit_depth;

  // ---------------------------------------------------------------------------
  // Device under test
  // ---------------------------------------------------------------------------
  ime_top #(
    .W_P      (W_P),
    .W_LOG    (W_LOG),
    .W_ACC    (W_ACC)
  ) dut (
    .clk            (clk),
    .rst_n          (rst_n),
    .s_axi_awaddr   (s_axi_awaddr),
    .s_axi_awvalid  (s_axi_awvalid),
    .s_axi_awready  (s_axi_awready),
    .s_axi_wdata    (s_axi_wdata),
    .s_axi_wstrb    (s_axi_wstrb),
    .s_axi_wvalid   (s_axi_wvalid),
    .s_axi_wready   (s_axi_wready),
    .s_axi_bresp    (s_axi_bresp),
    .s_axi_bvalid   (s_axi_bvalid),
    .s_axi_bready   (s_axi_bready),
    .s_axi_araddr   (s_axi_araddr),
    .s_axi_arvalid  (s_axi_arvalid),
    .s_axi_arready  (s_axi_arready),
    .s_axi_rdata    (s_axi_rdata),
    .s_axi_rresp    (s_axi_rresp),
    .s_axi_rvalid   (s_axi_rvalid),
    .s_axi_rready   (s_axi_rready),
    .s_axis_tdata   (s_axis_tdata),
    .s_axis_tuser   (s_axis_tuser),
    .s_axis_tvalid  (s_axis_tvalid),
    .s_axis_tready  (s_axis_tready),
    .s_axis_tlast   (s_axis_tlast),
    .m_axis_tdata   (m_axis_tdata),
    .m_axis_tuser   (m_axis_tuser),
    .m_axis_tvalid  (m_axis_tvalid),
    .m_axis_tready  (m_axis_tready),
    .m_axis_tlast   (m_axis_tlast),
    .error_flags    (error_flags),
    .poison_flag    (poison_flag),
    .bist_status    (bist_status),
    .credit_depth   (credit_depth)
  );

  // ---------------------------------------------------------------------------
  // UVM Runtime
  // ---------------------------------------------------------------------------
  initial begin
    // TODO: Initialize default stimulus, preload BIST vectors, configure agents.
    run_test();
  end

  // TODO: Drive default idle values onto interfaces until sequences run.
  initial begin
    s_axi_awaddr  = '0;
    s_axi_awvalid = 1'b0;
    s_axi_wdata   = '0;
    s_axi_wstrb   = '0;
    s_axi_wvalid  = 1'b0;
    s_axi_bready  = 1'b1;
    s_axi_araddr  = '0;
    s_axi_arvalid = 1'b0;
    s_axi_rready  = 1'b1;

    s_axis_tdata  = '0;
    s_axis_tuser  = '0;
    s_axis_tvalid = 1'b0;
    s_axis_tlast  = 1'b0;

    m_axis_tready = 1'b1;
  end

endmodule : tb_ime_top
