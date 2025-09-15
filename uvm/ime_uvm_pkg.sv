// ime_uvm_pkg.sv
// Skeleton UVM package for the Information Metrics Engine verification environment.
// Provides base sequence items, agents, environment, and smoke-test scaffolding.

package ime_uvm_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  import ime_bist_vectors_pkg::*;

  // Forward declarations -------------------------------------------------------
  class ime_env;
  class ime_base_test;

  // ---------------------------------------------------------------------------
  // Sequence Item
  // ---------------------------------------------------------------------------
  class ime_seq_item extends uvm_sequence_item;
    rand bit signed [15:0] prob_p;
    rand bit signed [15:0] prob_q;
    rand bit signed [15:0] log_weight;
    rand bit       [2:0]   mode_sel;
    rand bit       [1:0]   tree_sel;
    rand bit       [1:0]   pwl_region;
    rand bit       [3:0]   epsilon_bin;
    rand bit       [3:0]   delta_bin;

    `uvm_object_utils_begin(ime_seq_item)
      `uvm_field_int(prob_p,      UVM_ALL_ON)
      `uvm_field_int(prob_q,      UVM_ALL_ON)
      `uvm_field_int(log_weight,  UVM_ALL_ON)
      `uvm_field_int(mode_sel,    UVM_ALL_ON)
      `uvm_field_int(tree_sel,    UVM_ALL_ON)
      `uvm_field_int(pwl_region,  UVM_ALL_ON)
      `uvm_field_int(epsilon_bin, UVM_ALL_ON)
      `uvm_field_int(delta_bin,   UVM_ALL_ON)
    `uvm_object_utils_end

    constraint c_valid_bins {
      mode_sel    inside {[0:7]};
      tree_sel    inside {[0:3]};
      pwl_region  inside {[0:3]};
      epsilon_bin inside {[0:15]};
      delta_bin   inside {[0:15]};
    }

    function new(string name = "ime_seq_item");
      super.new(name);
    endfunction

    function void set_from_bist_sample(const ref ime_bist_sample_t sample);
      prob_p      = sample.prob_p;
      prob_q      = sample.prob_q;
      log_weight  = sample.log_weight;
      mode_sel    = sample.mode_sel;
      tree_sel    = sample.tree_sel;
      pwl_region  = sample.pwl_region;
      epsilon_bin = sample.epsilon_bin;
      delta_bin   = sample.delta_bin;
    endfunction

  endclass : ime_seq_item

  // ---------------------------------------------------------------------------
  // Sequencer and Sequence
  // ---------------------------------------------------------------------------
  class ime_sequencer extends uvm_sequencer #(ime_seq_item);
    `uvm_component_utils(ime_sequencer)

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction
  endclass : ime_sequencer

  class ime_bist_smoke_seq extends uvm_sequence #(ime_seq_item);
    `uvm_object_utils(ime_bist_smoke_seq)

    string vector_name = IME_BIST_VEC_UNIFORM;

    function new(string name = "ime_bist_smoke_seq");
      super.new(name);
    endfunction

    virtual task body();
      ime_seq_item                req;
      ime_bist_sample_queue_t     samples;

      samples = get_bist_vector(vector_name);

      foreach (samples[idx]) begin
        req = ime_seq_item::type_id::create($sformatf("req_%0d", idx));
        start_item(req);
        req.set_from_bist_sample(samples[idx]);
        finish_item(req);
      end
    endtask
  endclass : ime_bist_smoke_seq

  // ---------------------------------------------------------------------------
  // Driver
  // ---------------------------------------------------------------------------
  class ime_driver extends uvm_driver #(ime_seq_item);
    `uvm_component_utils(ime_driver)

    // TODO: Add virtual interface handles for AXI-Lite and stream BFMs.

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    virtual task run_phase(uvm_phase phase);
      ime_seq_item req;

      super.run_phase(phase);
      forever begin
        seq_item_port.get_next_item(req);
        // TODO: Drive 'req' onto the IME interfaces once BFMs are connected.
        seq_item_port.item_done();
      end
    endtask
  endclass : ime_driver

  // ---------------------------------------------------------------------------
  // Monitor
  // ---------------------------------------------------------------------------
  class ime_monitor extends uvm_monitor;
    `uvm_component_utils(ime_monitor)

    uvm_analysis_port #(ime_seq_item) analysis_port;

    function new(string name, uvm_component parent);
      super.new(name, parent);
      analysis_port = new("analysis_port", this);
    endfunction

    virtual task run_phase(uvm_phase phase);
      super.run_phase(phase);
      // TODO: Sample DUT transactions and publish via analysis_port using interface handles.
    endtask
  endclass : ime_monitor

  // ---------------------------------------------------------------------------
  // Agent
  // ---------------------------------------------------------------------------
  class ime_agent extends uvm_agent;
    `uvm_component_utils(ime_agent)

    ime_sequencer m_sequencer;
    ime_driver    m_driver;
    ime_monitor   m_monitor;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
      super.build_phase(phase);

      if (get_is_active() == UVM_ACTIVE) begin
        m_sequencer = ime_sequencer::type_id::create("m_sequencer", this);
        m_driver    = ime_driver::type_id::create("m_driver", this);
      end
      m_monitor = ime_monitor::type_id::create("m_monitor", this);
    endfunction

    virtual function void connect_phase(uvm_phase phase);
      super.connect_phase(phase);

      if (get_is_active() == UVM_ACTIVE) begin
        m_driver.seq_item_port.connect(m_sequencer.seq_item_export);
      end
    endfunction
  endclass : ime_agent

  // ---------------------------------------------------------------------------
  // Environment
  // ---------------------------------------------------------------------------
  class ime_env extends uvm_env;
    `uvm_component_utils(ime_env)

    ime_agent stream_agent;
    // TODO: Add scoreboard, coverage collectors, and configuration database hooks.

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      stream_agent = ime_agent::type_id::create("stream_agent", this);
    endfunction
  endclass : ime_env

  // ---------------------------------------------------------------------------
  // Base Test
  // ---------------------------------------------------------------------------
  class ime_base_test extends uvm_test;
    `uvm_component_utils(ime_base_test)

    ime_env env;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      env = ime_env::type_id::create("env", this);
    endfunction

    virtual task run_phase(uvm_phase phase);
      ime_bist_smoke_seq smoke_seq;

      phase.raise_objection(this);

      if (env != null && env.stream_agent != null &&
          env.stream_agent.m_sequencer != null) begin
        smoke_seq = ime_bist_smoke_seq::type_id::create("smoke_seq");
        smoke_seq.start(env.stream_agent.m_sequencer);
      end

      // TODO: Extend with targeted regressions and constrained random sequences.

      phase.drop_objection(this);
    endtask
  endclass : ime_base_test

endpackage : ime_uvm_pkg
