// bist_vectors.sv
// Placeholder BIST vectors for the IME verification environment.
// Encodes the Uniform, Dirac, and Symmetric Perturbation smoke patterns referenced in the freeze-pack spec.

package ime_bist_vectors_pkg;

  typedef struct packed {
    logic signed [15:0] prob_p;
    logic signed [15:0] prob_q;
    logic signed [15:0] log_weight;
    logic        [2:0]  mode_sel;
    logic        [1:0]  tree_sel;
    logic        [1:0]  pwl_region;
    logic        [3:0]  epsilon_bin;
    logic        [3:0]  delta_bin;
  } ime_bist_sample_t;

  typedef ime_bist_sample_t ime_bist_sample_queue_t[$];

  localparam string IME_BIST_VEC_UNIFORM      = "uniform";
  localparam string IME_BIST_VEC_DIRAC        = "dirac";
  localparam string IME_BIST_VEC_SYM_PERTURB  = "sym_perturb";

  function automatic ime_bist_sample_queue_t get_uniform_vector();
    ime_bist_sample_queue_t samples = {};

    samples.push_back('{
      prob_p:      16'sh0100,
      prob_q:      16'sh0100,
      log_weight:  16'sh0000,
      mode_sel:    3'd0,
      tree_sel:    2'd0,
      pwl_region:  2'd0,
      epsilon_bin: 4'd1,
      delta_bin:   4'd1
    });

    samples.push_back('{
      prob_p:      16'sh0080,
      prob_q:      16'sh0080,
      log_weight:  16'sh0000,
      mode_sel:    3'd0,
      tree_sel:    2'd1,
      pwl_region:  2'd1,
      epsilon_bin: 4'd2,
      delta_bin:   4'd2
    });

    samples.push_back('{
      prob_p:      16'sh0040,
      prob_q:      16'sh0040,
      log_weight:  16'sh0000,
      mode_sel:    3'd0,
      tree_sel:    2'd2,
      pwl_region:  2'd1,
      epsilon_bin: 4'd3,
      delta_bin:   4'd3
    });

    return samples;
  endfunction : get_uniform_vector

  function automatic ime_bist_sample_queue_t get_dirac_vector();
    ime_bist_sample_queue_t samples = {};

    samples.push_back('{
      prob_p:      16'sh4000,
      prob_q:      16'sh0000,
      log_weight:  16'sh3FFF,
      mode_sel:    3'd1,
      tree_sel:    2'd0,
      pwl_region:  2'd0,
      epsilon_bin: 4'd0,
      delta_bin:   4'd0
    });

    samples.push_back('{
      prob_p:      16'sh4000,
      prob_q:      16'sh0000,
      log_weight:  16'sh3FFF,
      mode_sel:    3'd1,
      tree_sel:    2'd1,
      pwl_region:  2'd0,
      epsilon_bin: 4'd0,
      delta_bin:   4'd1
    });

    return samples;
  endfunction : get_dirac_vector

  function automatic ime_bist_sample_queue_t get_sym_perturb_vector();
    ime_bist_sample_queue_t samples = {};

    samples.push_back('{
      prob_p:      16'sh0180,
      prob_q:      16'shFE80,
      log_weight:  16'sh0010,
      mode_sel:    3'd2,
      tree_sel:    2'd0,
      pwl_region:  2'd2,
      epsilon_bin: 4'd4,
      delta_bin:   4'd4
    });

    samples.push_back('{
      prob_p:      16'sh0180,
      prob_q:      16'sh0180,
      log_weight:  16'sh0010,
      mode_sel:    3'd2,
      tree_sel:    2'd1,
      pwl_region:  2'd2,
      epsilon_bin: 4'd5,
      delta_bin:   4'd5
    });

    samples.push_back('{
      prob_p:      16'sh0180,
      prob_q:      16'shFE80,
      log_weight:  16'sh0010,
      mode_sel:    3'd2,
      tree_sel:    2'd2,
      pwl_region:  2'd3,
      epsilon_bin: 4'd6,
      delta_bin:   4'd6
    });

    return samples;
  endfunction : get_sym_perturb_vector

  function automatic ime_bist_sample_queue_t get_bist_vector(string name);
    case (name)
      IME_BIST_VEC_UNIFORM:     return get_uniform_vector();
      IME_BIST_VEC_DIRAC:       return get_dirac_vector();
      IME_BIST_VEC_SYM_PERTURB: return get_sym_perturb_vector();
      default: begin
        $warning("ime_bist_vectors_pkg: Unknown vector '%s'. Returning empty pattern.", name);
        return {};
      end
    endcase
  endfunction : get_bist_vector

endpackage : ime_bist_vectors_pkg
