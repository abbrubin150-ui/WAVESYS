// ime_bist.sv
// Built-in self-test controller sourcing stimulus vectors and checking accumulated results for the IME.
// Supports Uniform/Dirac/SymPerturb sequences and updates CSR-visible status bits.
// Implements a simple stimulus generator with tolerance-based result checking to exercise the
// datapath skeleton, surfacing pass/fail status and poison injection for CSR visibility.

module ime_bist #(
  parameter int W_P      = 16,
  parameter int W_LOG    = 16,
  parameter int W_ACC    = 32,
  parameter int LUT_SIZE = 256,
  parameter int PWL_SEG  = 2,
  parameter int K_MAX    = 4096
) (
  input  logic                       clk,
  input  logic                       rst_n,

  // Control from CSR block
  input  logic [1:0]                 bist_cmd,
  input  logic [2:0]                 vect_sel,
  input  logic [7:0]                 tol,
  input  logic [15:0]                frame_len,

  // Stimulus output toward stream interface
  output logic                       bist_active,
  output logic [W_P*2+W_LOG-1:0]     bist_tdata,
  output logic [7:0]                 bist_tuser,
  output logic                       bist_tvalid,
  input  logic                       bist_tready,
  output logic                       bist_tlast,

  // Observation from accumulator output
  input  logic [W_ACC-1:0]           obs_acc,
  input  logic [7:0]                 obs_tuser,
  input  logic                       obs_valid,
  input  logic                       obs_last,

  // Status back to CSR
  output logic [1:0]                 bist_status,
  output logic                       poison_inject
);

  typedef struct packed {
    logic [W_P-1:0]   prob_p;
    logic [W_P-1:0]   prob_q;
    logic [W_LOG-1:0] score;
  } bist_vector_t;

  localparam int unsigned BIST_DEPTH = 8;

  typedef enum logic [1:0] {
    ST_IDLE   = 2'b00,
    ST_STREAM = 2'b01,
    ST_WAIT   = 2'b10,
    ST_DONE   = 2'b11
  } bist_state_t;

  localparam logic [1:0] STATUS_IDLE = 2'b00;
  localparam logic [1:0] STATUS_RUN  = 2'b01;
  localparam logic [1:0] STATUS_PASS = 2'b10;
  localparam logic [1:0] STATUS_FAIL = 2'b11;

  function automatic logic [15:0] clamp_frame_len(input logic [15:0] cfg_len);
    logic [15:0] limit;
    logic [15:0] result;
    limit  = 16'(BIST_DEPTH);
    result = cfg_len;
    if (result == 16'd0) begin
      result = limit;
    end
    if (result > limit) begin
      result = limit;
    end
    if (result == 16'd0) begin
      result = 16'd1;
    end
    return result;
  endfunction

  localparam int unsigned TOL_EXT_PAD = (W_ACC > 8) ? (W_ACC - 8) : 0;

  function automatic logic [W_ACC-1:0] extend_tol(input logic [7:0] tol_value);
    extend_tol = {{TOL_EXT_PAD{1'b0}}, tol_value};
  endfunction

  function automatic bist_vector_t vect_lookup(
    input logic [2:0]  sel,
    input logic [15:0] index
  );
    bist_vector_t vect;
    logic [1:0]    ridx;

    vect = '{default: '0};
    ridx = index[1:0];

    case (sel)
      3'd0: begin // Uniform
        case (ridx)
          2'd0: vect = '{prob_p: W_P'(16'd1024), prob_q: W_P'(16'd1024), score: W_LOG'(16'd2048)};
          2'd1: vect = '{prob_p: W_P'(16'd1024), prob_q: W_P'(16'd2048), score: W_LOG'(16'd1536)};
          2'd2: vect = '{prob_p: W_P'(16'd2048), prob_q: W_P'(16'd1024), score: W_LOG'(16'd1280)};
          default: vect = '{prob_p: W_P'(16'd2048), prob_q: W_P'(16'd2048), score: W_LOG'(16'd1024)};
        endcase
      end
      3'd1: begin // Dirac spike on p-channel
        case (ridx)
          2'd0: vect = '{prob_p: W_P'(16'd4096), prob_q: W_P'(16'd128), score: W_LOG'(16'd4096)};
          2'd1: vect = '{prob_p: W_P'(16'd64),   prob_q: W_P'(16'd128), score: W_LOG'(16'd256)};
          default: vect = '{prob_p: W_P'(16'd32), prob_q: W_P'(16'd256), score: W_LOG'(16'd128)};
        endcase
      end
      3'd2: begin // Symmetric perturbation
        case (ridx)
          2'd0: vect = '{prob_p: W_P'(16'd1536), prob_q: W_P'(16'd1664), score: W_LOG'(16'd1408)};
          2'd1: vect = '{prob_p: W_P'(16'd1664), prob_q: W_P'(16'd1536), score: W_LOG'(16'd1344)};
          default: vect = '{prob_p: W_P'(16'd1600), prob_q: W_P'(16'd1600), score: W_LOG'(16'd1312)};
        endcase
      end
      default: begin
        vect = '{prob_p: W_P'(16'd0), prob_q: W_P'(16'd0), score: W_LOG'(16'd0)};
      end
    endcase
    return vect;
  endfunction

  function automatic logic [W_ACC-1:0] expected_lookup(input logic [2:0] sel);
    logic [W_ACC-1:0] result;
    case (sel)
      3'd0: result = W_ACC'(32'd4096);
      3'd1: result = W_ACC'(32'd8192);
      3'd2: result = W_ACC'(32'd2048);
      default: result = '0;
    endcase
    return result;
  endfunction

  bist_state_t          state_reg;
  bist_state_t          state_next;
  logic [15:0]          index_reg;
  logic [15:0]          index_next;
  logic [15:0]          frame_len_reg;
  logic [15:0]          frame_len_next;
  logic [2:0]           vect_sel_reg;
  logic [2:0]           vect_sel_next;
  logic [W_ACC-1:0]     expected_reg;
  logic [W_ACC-1:0]     expected_next;
  logic [1:0]           status_reg;
  logic [1:0]           status_next;
  logic                 poison_reg;
  logic                 poison_next;

  logic [W_ACC-1:0]     tol_ext;
  logic [15:0]          last_index;
  bist_vector_t         stream_vector;

  assign tol_ext      = extend_tol(tol);
  assign last_index   = (frame_len_reg == 16'd0) ? 16'd0 : (frame_len_reg - 16'd1);
  assign stream_vector= vect_lookup(vect_sel_reg, index_reg);

  assign bist_active  = (state_reg == ST_STREAM) || (state_reg == ST_WAIT);
  assign bist_tvalid  = (state_reg == ST_STREAM);
  assign bist_tdata   = {stream_vector.prob_p, stream_vector.prob_q, stream_vector.score};
  assign bist_tuser   = {vect_sel_reg, index_reg[4:0]};
  assign bist_tlast   = (state_reg == ST_STREAM) && (index_reg == last_index);
  assign bist_status  = status_reg;
  assign poison_inject= poison_reg;

  logic [W_ACC-1:0]     diff_value;
  logic                 mismatch;

  always_comb begin
    state_next      = state_reg;
    index_next      = index_reg;
    frame_len_next  = frame_len_reg;
    vect_sel_next   = vect_sel_reg;
    expected_next   = expected_reg;
    status_next     = status_reg;
    poison_next     = poison_reg;
    diff_value      = '0;
    mismatch        = 1'b0;

    case (state_reg)
      ST_IDLE: begin
        if (bist_cmd == 2'b01) begin
          frame_len_next = clamp_frame_len(frame_len);
          vect_sel_next  = vect_sel;
          expected_next  = expected_lookup(vect_sel);
          index_next     = 16'd0;
          state_next     = ST_STREAM;
          status_next    = STATUS_RUN;
          poison_next    = 1'b0;
        end else if (bist_cmd == 2'b10) begin
          status_next = STATUS_IDLE;
          poison_next = 1'b0;
        end
      end
      ST_STREAM: begin
        if (bist_cmd == 2'b10) begin
          state_next  = ST_IDLE;
          status_next = STATUS_IDLE;
          poison_next = 1'b0;
          index_next  = 16'd0;
        end else if (bist_cmd == 2'b01) begin
          frame_len_next = clamp_frame_len(frame_len);
          vect_sel_next  = vect_sel;
          expected_next  = expected_lookup(vect_sel);
          index_next     = 16'd0;
          status_next    = STATUS_RUN;
          poison_next    = 1'b0;
        end else if (bist_tvalid && bist_tready) begin
          if (index_reg == last_index) begin
            state_next = ST_WAIT;
          end else begin
            index_next = index_reg + 16'd1;
          end
        end
      end
      ST_WAIT: begin
        if (bist_cmd == 2'b10) begin
          state_next  = ST_IDLE;
          status_next = STATUS_IDLE;
          poison_next = 1'b0;
        end else if (obs_valid && obs_last) begin
          diff_value = (obs_acc >= expected_reg) ? (obs_acc - expected_reg) : (expected_reg - obs_acc);
          mismatch   = (obs_tuser[7:5] != vect_sel_reg) || (obs_tuser[4:0] != last_index[4:0]);
          if (!mismatch && diff_value <= tol_ext) begin
            status_next = STATUS_PASS;
            poison_next = 1'b0;
          end else begin
            status_next = STATUS_FAIL;
            poison_next = 1'b1;
          end
          state_next = ST_DONE;
        end
      end
      ST_DONE: begin
        if (bist_cmd == 2'b01) begin
          frame_len_next = clamp_frame_len(frame_len);
          vect_sel_next  = vect_sel;
          expected_next  = expected_lookup(vect_sel);
          index_next     = 16'd0;
          state_next     = ST_STREAM;
          status_next    = STATUS_RUN;
          poison_next    = 1'b0;
        end else if (bist_cmd == 2'b10) begin
          state_next  = ST_IDLE;
          status_next = STATUS_IDLE;
          poison_next = 1'b0;
        end
      end
      default: begin
        state_next  = ST_IDLE;
        status_next = STATUS_IDLE;
        poison_next = 1'b0;
      end
    endcase
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_reg     <= ST_IDLE;
      index_reg     <= 16'd0;
      frame_len_reg <= 16'd1;
      vect_sel_reg  <= 3'd0;
      expected_reg  <= '0;
      status_reg    <= STATUS_IDLE;
      poison_reg    <= 1'b0;
    end else begin
      state_reg     <= state_next;
      index_reg     <= index_next;
      frame_len_reg <= frame_len_next;
      vect_sel_reg  <= vect_sel_next;
      expected_reg  <= expected_next;
      status_reg    <= status_next;
      poison_reg    <= poison_next;
    end
  end

endmodule : ime_bist

