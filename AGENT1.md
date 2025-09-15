# AGENT.md — IME Freeze Pack v0.1

Deterministic agent playbook for **publishing the IME Freeze Pack v0.1** as a GitHub‑ready repository, with docs, RTL/UVM/formal skeletons, CI, and auditable execution.

> **Scope**: One‑shot publish of the frozen spec into a repo `ime-freeze-pack-v0` without changing the Freeze Pack content. All additions are scaffolding and automation only.

---

## 0) Operating Model

**Determinism + Monotonicity + Audit**

* **EXACT1 gating**: One of {EXECUTE, HOLD, ESCALATE} must be true at each decision point.
* **Monotonic guards**: \Phi, iter, CANON5, K never decrease once raised; **locks** at thresholds: \Phi≥0.90, iter≥7, CANON5≥4, K≥1.
* **Fail‑closed (POISON)**: On invariant breach → stop, emit audit, no partial writes.
* **Auditor (∴)**: Log **Intent → Execution → Outcome → Δ** per step. Persist transcript to `/logs/agent_audit.jsonl`.
* **Idempotent**: Re‑runs produce identical tree unless inputs change (hash inputs; avoid nondeterminism).

**WHY/HOW tri‑block**
WHY: reproducible bridge spec→RTL→IP.
HOW: mirror spec → scaffold code → validate with CI.
Early‑Stop: after green CI + published docs.

---

## 1) Inputs & Preconditions

* `FREEZE_PACK.md`: the translated v0.1 spec (immutable).
* GitHub token with repo+pages scopes.
* Tooling available in runner: `git`, `node>=18`, `python3`, `verilator`, `graphviz` (optional), `pandoc` (optional).

**Sanity checks**

* Spec SHA256 pinned.
* No repo named `ime-freeze-pack-v0` exists under the target org, or agent owns it.
* Time source fixed (UTC) for timestamps.

---

## 2) Repository Creation

**Goal**: Create `ime-freeze-pack-v0` with Apache‑2.0, branches `main` (protected) and `dev` (default).

**Steps**

1. Create repo.
2. Create branches and protections (require PRs, 1 reviewer, linear history).
3. Add templates:

   * `.gitignore` (HDL/Vivado/Quartus/ModelSim)
   * `LICENSE` (Apache‑2.0)
   * `README.md` (auto‑generated summary; see §6)

**Checks**

* `git ls-remote` shows both branches.
* Protections set via API; print policy JSON to audit.

---

## 3) Documentation Layout

```
/docs/
  IME_Spec_FreezePack_v0.1.md   # verbatim translated spec
  CSR_Map.md                    # CSR tables extracted
  Pipeline.md                   # ASCII + figures refs
  Verification.md               # BIST vectors, SVA templates
  IP_Claims.md                  # concise claims
/figs/                          # pipeline/FSM/dataflow
```

**Rules**

* **Never overwrite** `/docs/IME_Spec_FreezePack_v0.1.md`.
* Keep CSR tables **canonical** with RTL params (single source of truth: CSR\_Map.md).
* All figures referenced relative to `/figs`.

---

## 4) RTL Skeleton (/rtl)

Create empty compile‑clean SystemVerilog modules with parameterized headers:

* `ime_top.sv`
* `ime_axi_lite_csr.sv`
* `ime_stream_if.sv`
* `ime_log2_adapt.sv`
* `ime_coreop.sv`
* `ime_acc_tree.sv`
* `ime_fisher.sv`
* `ime_joint_framer.sv`
* `ime_bist.sv`

**Header template**

```systemverilog
module ime_top #(
  parameter int W_P = 16,
  parameter int W_LOG = 16,
  parameter int LUT_SIZE = 256,
  parameter int PWL_SEG = 2
) (
  input  logic         clk,
  input  logic         rst_n,
  // ready/valid streaming input
  input  logic         in_valid,
  output logic         in_ready,
  input  logic [W_P-1:0] p_data,
  input  logic [W_P-1:0] q_data,
  // control/status CSR AXI-Lite
  // ...
  // streaming output
  output logic         out_valid,
  input  logic         out_ready,
  output logic [W_LOG-1:0] metric
);
// TODO: instantiate ime_coreop, ime_acc_tree, ime_log2_adapt, ime_fisher
endmodule
```

**One‑hot/EXACT1 enforcement snippet** (CSR decode)

```systemverilog
logic [2:0] mode_sel; // one-hot
assert property (@(posedge clk) disable iff(!rst_n) $onehot0(mode_sel));
// Poison on illegal combo
always_comb if (^mode_sel !== 1'b1) begin
  // set error CSR bit, block state updates
end
```

---

## 5) Verification (/uvm, /formal)

**/uvm/**

* `tb_ime_top.sv` — clock/reset, AXI‑Lite model, stream BFMs.
* `ime_uvm_pkg.sv` — env/agent/sequencer/driver/monitor skeletons.
* `bist_vectors.sv` — Uniform, Dirac, SymPerturb patterns.

**/formal/**

* `sva_assertions.sv` — ready/valid, \$onehot0, monotonic locks.
* `cover_points.sv` — MODE×TREE×PWL×eps×delta coverage bins.

**Property examples**

```systemverilog
// Monotonic locks once thresholds reached
property lock_phi; @(posedge clk) disable iff(!rst_n)
  (phi_q >= 16'd0) |=> ((phi_q >= TH_PHI) -> (phi_d >= TH_PHI));
endproperty
assert property(lock_phi);
```

---

## 6) CI/CD Workflows (.github/workflows)

**rtl-ci.yml**

```yaml
name: RTL CI
on: [push, pull_request]
jobs:
  lint-sim:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with: { python-version: '3.x' }
      - name: Install tools
        run: |
          sudo apt-get update
          sudo apt-get install -y verilator
      - name: Lint RTL
        run: verilator --lint-only $(git ls-files 'rtl/*.sv')
      - name: Dummy sim build
        run: |
          mkdir -p build && cd build
          verilator -cc ../rtl/ime_top.sv --exe ../uvm/tb_ime_top.sv || true
```

**docs.yml**

```yaml
name: Docs
on: [push]
permissions: { contents: write, pages: write, id-token: write }
concurrency: docs
jobs:
  build-deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Validate CSR tables
        run: python3 - << 'PY'
import re,sys
s=open('docs/CSR_Map.md').read()
assert re.search(r'^\|\s*Register', s, re.M), 'CSR table missing header'
print('CSR OK')
PY
      - uses: actions/configure-pages@v5
      - uses: actions/upload-pages-artifact@v3
        with: { path: 'docs' }
      - uses: actions/deploy-pages@v4
```

---

## 7) README.md Synthesis

Generate a concise README from the spec and link to `/docs/IME_Spec_FreezePack_v0.1.md`.

**README seed**

```md
# IME Freeze Pack v0.1
Apache-2.0 • deterministic scaffolding for Information Metrics Engine.

- Spec: [/docs/IME_Spec_FreezePack_v0.1.md](docs/IME_Spec_FreezePack_v0.1.md)
- CSR: [/docs/CSR_Map.md](docs/CSR_Map.md)
- Pipeline: [/docs/Pipeline.md](docs/Pipeline.md)
- Verification: [/docs/Verification.md](docs/Verification.md)
- IP Claims: [/docs/IP_Claims.md](docs/IP_Claims.md)

## Build
See CI workflow; local lint via `verilator --lint-only rtl/*.sv`.
```

Tag release `v0.1-freeze` after first green CI.

---

## 8) Versioning & Open Items

* Maintain `/open_issues.md` with **DELTA\_THRESH** default and **K\_MAX** decisions.
* Versioning: v0.1 (frozen) → v0.2… until tape‑out. Never rewrite history; append new spec versions.

---

## 9) Agent Policy & Invariants

**State metrics** (mirrors prior work): `Φ_struct` (Φ), `iter_logic` (iter), `CANON5`, `K`.

* **Monotonic**: once raised, cannot regress.
* **Locks**: Φ≥0.90, iter≥7, CANON5≥4, K≥1 → protect with SVA and CI checks.
* **Poison**: violation sets error CSR and halts automation.

**Decision table**

* EXECUTE: Preconditions met, CI green expected.
* HOLD: Missing info, failing invariants, or doc/RTL divergence.
* ESCALATE: Permissions, conflicting CSR maps, or spec hash mismatch.

---

## 10) Auditor (∴) — Minimal Schema

Append one JSON line per step to `/logs/agent_audit.jsonl`:

```json
{
  "ts": "2025-09-15T21:00:00Z",
  "intent": "create repo & push skeleton",
  "execution": "init repo, push templates",
  "outcome": "repo created, ci queued",
  "delta": ""
}
```

Summarize at end: Φ, iter, CANON5, K; EXACT1 decision; CI result URLs.

---

## 11) Idempotence & Rollback

* Detect existing repo → **idempotent** path (validate structure; update CI only).
* On failure, **no destructive** actions. Emit remediation plan instead.

---

## 12) OpenAPI/CLI Hooks (optional)

* `tools/make_readme.py` — synthesize README from spec.
* `tools/validate_csr.py` — cross‑check CSR params vs RTL headers.
* `tools/gen_figs.sh` — render ASCII→SVG if Graphviz is available.

---

## 13) QuickStart (for humans)

```bash
# clone
git clone https://github.com/<org>/ime-freeze-pack-v0 && cd ime-freeze-pack-v0
# lint RTL
verilator --lint-only rtl/*.sv
# view docs
xdg-open docs/IME_Spec_FreezePack_v0.1.md
```

---

## 14) Atomic Paragraph — Execution Closure

Agent task: publish IME Freeze Pack as GitHub repo with docs/rtl/uvm/formal structured; enforce EXACT1/Poison/SVA contracts; CI pipelines validate consistency.
WHY: ensure reproducible flow bridging spec→RTL→IP.
HOW: mirror Freeze Pack → skeletonize RTL/UVM → run CI. **Early‑Stop** once Verilator lint + Docs build pass.
