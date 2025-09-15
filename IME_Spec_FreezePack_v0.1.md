# Information Metrics Engine (IME) — Micro‑Architecture Specification

**Freeze Pack v0.1 — Single Source of Truth for RTL / Verification / Software**

> This document freezes interfaces, processing pipeline, numeric formats, algorithms, security/DFT mechanisms, and IP claim essentials. Any future modification must be tracked in the version history section.

---

## Part I — System Architecture & Interfaces

### I.1 Top‑Level Integration in SoC

* **Control Plane**: MMIO/AXI‑Lite connection to the CSR bank.
* **Data Plane**: AXI4‑Stream‑like on all inputs/outputs with Ready/Valid.
* **Back‑Pressure**: Downstream credit‑based flow control + orderly pipeline stall.
* **Performance Target**: **II=1** (one bin per clock) with configuration‑dependent total latency (detailed in Part II.2).
* **Security**: Exact1 Gating + constant‑time execution (CONST\_TIME\_CYCLES).

### I.2 Control/Status Register Map (CSR, MMIO)

#### Base Addresses (offset from IME\_BASE)

| Addr   | Reg        | Bitfield | Field               | Access | Reset    | Description                                                                                                       |
| ------ | ---------- | -------- | ------------------- | ------ | -------- | ----------------------------------------------------------------------------------------------------------------- |
| 0x0000 | CFG0       | \[4:0]   | MODE\_onehot        | RW     | 5'b00001 | One‑hot mode select (H/CE/KL/MI/Fisher). Enables **EXACT1**. Illegal multi‑hot combinations are hardware‑blocked. |
|        |            |          | TREE\_TYPE          | RW     | 1'b0     | Accumulator topology: 0=sequential, 1=Kogge‑Stone. Impacts latency/frequency/area.                                |
|        |            | \[15:8]  | LUT\_SIZE           | RW     | 8'd256   | ROM size for log2(1+x) approximation.                                                                             |
|        |            |          | PWL\_SEGMENTS       | RW     | 2'b10    | # of PWL segments: {0,2,4}.                                                                                       |
|        |            | \[29:16] | CONST\_TIME\_CYCLES | RW     | 14'h0    | NOP padding per frame for constant‑time execution.                                                                |
| 0x0004 | CFG1       | \[11:0]  | QP\_FRAC            | RW     | 12'd15   | Q‑format for probabilities (default Q1.15: INT=1, FRAC=15).                                                       |
|        |            | \[23:12] | QLOG\_FRAC          | RW     | 12'd14   | Q‑format for log values (recommend Q2.14/Q5.11 per profile).                                                      |
| 0x0008 | CFG2       | \[15:0]  | EPSILON\_Q          | RW     | 16'h0001 | ε‑floor to prevent log(0) on p/q.                                                                                 |
|        |            | \[31:16] | DELTA\_THRESH       | RW     | 16'h0001 | Error threshold ∣Δ∣ to trigger PWL (accuracy↔power).                                                              |
| 0x000C | CFG3       | \[15:0]  | CREDIT\_DEPTH       | RO     | –        | Reported downstream credit depth.                                                                                 |
|        |            | \[31:16] | FRAME\_LEN          | RW     | 16'h1000 | Number of bins per frame (K). Reconfigurable between frames.                                                      |
| 0x0010 | STAT       | \[3:0]   | ERROR\_FLAGS        | RO,W1C | 4'h0     | Sticky flags: UNDERFLOW/OVERFLOW/NEGLOG/DIV0.                                                                     |
|        |            |          | POISON              | RO     | 1'b0     | Frame‑level sticky flag invalidating the entire frame result.                                                     |
|        |            | \[6:5]   | BIST\_STATUS        | RO     | 2'b00    | PASS/FAIL status for BIST engine.                                                                                 |
| 0x0014 | BIST\_CTRL | \[1:0]   | BIST\_CMD           | WO     | –        | START/STOP.                                                                                                       |
|        |            | \[4:2]   | VECT\_SEL           | RW     | 3'b000   | Uniform / Dirac / SymPerturb.                                                                                     |
|        |            | \[15:8]  | TOL                 | RW     | 8'h01    | Tolerance (in accumulator LSBs) for BIST checks.                                                                  |

> **Architectural Note**: CSR set enables post‑silicon tuning (PPA & Security). **Exact1** is enforced in hardware (one‑hot hardening) to prevent multi‑hot faults.

---

## Part II — Processing Pipeline

### II.1 Stages S0–S6 and Gating

| Stage | Role             | Latency (clk) | Controls                     | Gating Signals    | Implementation Notes                                |
| ----- | ---------------- | ------------- | ---------------------------- | ----------------- | --------------------------------------------------- |
| S0    | Framer + ε‑floor | 1             | EPSILON\_Q, FRAME\_LEN       | –                 | Counter/comparator/MUX; first guard against log(0). |
| S1    | Normalize + LZC  | 1–2           | –                            | –                 | Barrel‑shifter + LZC; prepares mantissa.            |
| S2    | LUT Read         | 1             | LUT\_SIZE                    | –                 | Synchronous BRAM/ROM; area scales with table size.  |
| S3    | PWL Refine       | 1             | PWL\_SEGMENTS, DELTA\_THRESH | use\_pwl          | FMA (m·x+c); clock‑gated stage.                     |
| S4    | Core Op          | 1–2           | MODE\_onehot                 | cen\_H/CE/KL/MI/F | NR loop / mul‑acc ops.                              |
| S5    | Accumulate       | 1 or log(N)   | TREE\_TYPE                   | –                 | Sequential accumulator / Kogge‑Stone tree.          |
| S6    | Finalize + Pad   | 0..K          | CONST\_TIME\_CYCLES          | –                 | Output holding until constant‑time budget expires.  |

### II.2 Back‑Pressure & Freeze Behavior

* **Freezable**: no implicit flush; each stage has clock‑enable derived from next‑stage ready.
* **II=1** is preserved; total latency = sum of stage latencies for the current configuration.

---

## Part III — Fixed‑Point Arithmetic (Q) & Error Budgeting

### III.1 Formats & Error Targets

* **Qp**: default **Q1.15** for p,q.
* **Qlog**: recommended **Q2.14** or **Q5.11** per dynamic range.
* **Target**: $E_{total} < 0.25$ accumulator LSB per frame.
* **Tuning**: **DELTA\_THRESH** is the main accuracy↔power knob; to be characterized in verification.

### III.2 Adaptive log₂ Core (Innovation)

* Decomposition: **LZC → LUT → PWL**.
* Online error **∣Δ∣=∣PWL−LUT∣**; gate S3 based on **DELTA\_THRESH**.
* **Accuracy‑driven power management**: enable PWL only when needed.

### III.3 High‑Throughput Division (NR) for MI/Fisher

* **Range reduction** to d∈\[0.5,1).
* **Seed LUT**: 8–10 effective bits.
* **2–3 iterations** for \~16–18 bits; reuse S4 multipliers; localized pipeline pause for NR.

---

## Part IV — Hardware Reuse Across Metrics (H/CE/KL/MI/Fisher)

* **Common Atom**: $-p·log2(p)$ (H/CE/KL).
* **KL**: subtract **before** accumulation: $(-p·log2 q)−(−p·log2 p)$ to save N mul+add.
* **MI**: Joint‑Framer for p(x,y); dual‑port BRAM for marginals p(x), p(y); reuse log2(p(x)), log2(p(y)).
* **Fisher**: $acc+=p·score^2$; two‑pass mode for score‑based feature selection.

---

## Part V — Security & Resilience

### V.1 Constant‑Time Execution (CONST\_TIME\_CYCLES)

* Per‑frame NOP padding; timing anchored in S6; constant per selected mode.

### V.2 EXACT1 (Power & SCA)

* MODE\_onehot → per‑branch **clock/power gating** via cen\_\*; inactive branches are fully quiesced.

### V.3 Sticky, Propagating Poison‑Bit

* OR of ERROR\_FLAGS; sticky until frame\_end; propagated alongside data to output; **system contract**: valid output ⇔ POISON=0.

---

## Part VI — DFT, Verification & BIST

### VI.1 BIST Vectors & Golden Checks

| VECT\_SEL  | Description      | Settings     | Expected Acc (symbolic)             | Expected STAT | TOL | Coverage                       |
| ---------- | ---------------- | ------------ | ----------------------------------- | ------------- | --- | ------------------------------ |
| Uniform    | p\_i=1/K         | FRAME\_LEN=K | H≈log2(K)                           | 0             | TOL | Full datapath + normalization  |
| Dirac      | p\_k=1, others 0 | FRAME\_LEN=K | H=0; CE=−log2(q\_k); KL=−log2(q\_k) | 0             | TOL | p∈{0,1}, log(1)=0              |
| SymPerturb | p=1/K±δ          | FRAME\_LEN=K | KL≈(1/K·ln2)·2∑δ\_i^2               | 0             | TOL | Fine‑accuracy + KL subtraction |

### VI.2 Minimal SVA Templates

```systemverilog
// EXACT1 — exactly one bit set
assert property (@(posedge clk) disable iff(!rst_n)
  $onehot(MODE_onehot));

// Poison sticky until frame end
assert property (@(posedge clk) POISON |-> s_until(frame_end));

// Constant‑time: frame_start → frame_done after CONST_TIME_CYCLES
assert property (@(posedge clk)
  frame_start |=> ##[CONST_TIME_CYCLES:CONST_TIME_CYCLES] frame_done);

// Ready/Valid: no valid output on poisoned frame
assert property (@(posedge clk)
  (out_valid && out_ready) |-> (POISON==0));

// No‑X on outputs
assert property (@(posedge clk) !$isunknown({out_valid,out_data,POISON}));
```

### VI.3 Coverage Matrix (Sketch)

* Modes: MODE×TREE×PWL×ε×Δ.
* Corners: p≈0, p≈1, q≈0 (with ε), small/large symmetric δ.
* Scenarios: sustained back‑pressure; changing FRAME\_LEN between frames; attempted multi‑hot (blocked).

---

## Part VII — RTL Layering & Interfaces (Requirements)

* **Top Modules**: `ime_top`, `ime_axi_lite_csr`, `ime_stream_if`, `ime_log2_adapt`, `ime_coreop`, `ime_acc_tree`, `ime_fisher`, `ime_joint_framer`, `ime_bist`.
* **Parameters**: `W_P`, `W_LOG`, `W_ACC`, `LUT_SIZE`, `PWL_SEG`, `K_MAX`.
* **Artifacts**: Framer FSM diagram; datapath with cen\_\*; credit‑flow diagram.

---

## Part VIII — IP Claims (Executive Summary)

1. **Adaptive log₂ core**: LZC/LUT/PWL with online ∣Δ∣ measurement and dynamic gating of S3 via **DELTA\_THRESH**.
2. **EXACT1 + constant‑time**: one‑hot→per‑branch clock/power‑gating + per‑frame NOP padding.
3. **Chained Poison**: frame‑sticky flag propagated through the pipeline, invalidating the entire frame end‑to‑end.
   **Dependents**: reuse for KL/MI; Joint‑Framer; CSR‑selected acc‑tree; information‑theory‑aware BIST.

---

## Part IX — Open Items & Freeze Decisions

* Default value for **DELTA\_THRESH** (to be fixed via characterization on representative datasets).
* Maximum **K\_MAX/FRAME\_LEN** (affects register widths, BRAM load, Kogge‑Stone depth).
* Final **Error‑Budget**: contributions (LUT vs. PWL vs. NR) and field widths optimization.

---

## Part X — Integration Procedure & Implementation Path

1. RTL freeze → early synthesis (PPA report for TREE/PWL variants).
2. UVM + formal (SVA above) + BIST in sim.
3. FPGA bring‑up (functional/timing; measure power vs. use\_pwl rate).
4. PPA tuning → CSR default values.
5. Provisional filing with §VIII claims and drawings.

---

## Appendix A — MODE\_onehot Encoding & Hardening

* Multi‑hot blocking: `if (!$onehot(MODE_onehot)) MODE_onehot <= 5'b00001;` (or assert/NMI).
* One‑to‑one cen\_\* decoder; reset‑safe.

## Appendix B — AXI‑Stream Interfaces

* Signals: `tdata[tuser:0]`, `tvalid`, `tready`, `tlast` as frame\_end.
* Full bidirectional stall support.

## Appendix C — NAND‑Only Implementations (Quick Map)

* NOT/AND/OR/XOR from NAND; Full‑Adder=9×NAND; LZC via priority encoders; Barrel‑shifter as MUX network (2:1=4×NAND); LUT as SRAM/ROM.

---

## Version History

* **v0.1 (Freeze)**: CSR/PIPE/Q/DFT/IP frozen; open: DELTA\_THRESH, K\_MAX.

---

### Atomic Paragraph (Freeze Closure)

Conversation Output: the spec consolidates IME as the source of truth, aligning RTL/verification/software around CSR, II=1 pipeline, adaptive log₂, EXACT1, and Poison.
WHY: guarantee accuracy‑power‑security balance under deterministic timing.
HOW (3): (1) hardened one‑hot CSR; (2) log₂ with ∣Δ∣→gating; (3) Poison+BIST+SVA for proof.
\[Early‑Stop] defaults: PWL=2, LUT=256, CONST=0 — until characterization data is in.
