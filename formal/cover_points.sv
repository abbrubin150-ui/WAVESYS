// cover_points.sv
// Functional coverage scaffolding for the IME formal testbench. Tracks MODE×TREE×PWL×ε×Δ
// combinations to ensure representative operating points are exercised.

module ime_cover_points #(
  parameter int MODE_WIDTH  = 3,
  parameter int TREE_WIDTH  = 2,
  parameter int PWL_WIDTH   = 2,
  parameter int EPS_WIDTH   = 4,
  parameter int DELTA_WIDTH = 4
) (
  input logic                       clk,
  input logic                       rst_n,
  input logic [MODE_WIDTH-1:0]      mode_sel,
  input logic [TREE_WIDTH-1:0]      tree_sel,
  input logic [PWL_WIDTH-1:0]       pwl_region,
  input logic [EPS_WIDTH-1:0]       epsilon_bin,
  input logic [DELTA_WIDTH-1:0]     delta_bin,
  input logic                       sample_valid
);

  // Coverage over MODE×TREE×PWL×ε×Δ selection fields.
  covergroup cg_operating_modes @(posedge clk iff (sample_valid && rst_n));
    option.per_instance = 1;

    mode_cp : coverpoint mode_sel {
      bins uniform      = {0};
      bins dirac        = {1};
      bins sym_perturb  = {2};
      bins reserved[]   = {[3:(1<<MODE_WIDTH)-1]};
    }

    tree_cp : coverpoint tree_sel {
      bins tree_bins[] = {[0:(1<<TREE_WIDTH)-1]};
    }

    pwl_cp : coverpoint pwl_region {
      bins pwl_bins[] = {[0:(1<<PWL_WIDTH)-1]};
    }

    epsilon_cp : coverpoint epsilon_bin {
      bins epsilon_low  = {[0:((1<<EPS_WIDTH)/4)-1]};
      bins epsilon_mid  = {[((1<<EPS_WIDTH)/4):((1<<EPS_WIDTH)/2)-1]};
      bins epsilon_high = {[((1<<EPS_WIDTH)/2): (1<<EPS_WIDTH)-1]};
    }

    delta_cp : coverpoint delta_bin {
      bins delta_low  = {[0:((1<<DELTA_WIDTH)/4)-1]};
      bins delta_mid  = {[((1<<DELTA_WIDTH)/4):((1<<DELTA_WIDTH)/2)-1]};
      bins delta_high = {[((1<<DELTA_WIDTH)/2):(1<<DELTA_WIDTH)-1]};
    }

    // Pairwise and full cross-coverage encourage breadth of exploration.
    mode_tree_cross    : cross mode_cp, tree_cp;
    mode_tree_pwl_cross: cross mode_cp, tree_cp, pwl_cp;
    full_operating_cross: cross mode_cp, tree_cp, pwl_cp, epsilon_cp, delta_cp;
  endgroup

  cg_operating_modes cg_inst = new();

endmodule : ime_cover_points
