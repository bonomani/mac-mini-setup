# BGS Entry

project_name: mac-mini-setup
bgs_slice: BGS-State-Modeled-Governed
decision_reason: "AI workstation setup depends on explicit installation,
  configuration, readiness, runtime, and recovery semantics across 9
  components (7 software + 1 system + 1 verification). Preflight gate
  (supported-platform) and UCC convergence are interpreted against an
  ASM-aligned setup state model with parametric state for value-convergence
  targets. Capability targets replace most gates for precondition checks.
  TIC verification provides post-convergence evidence. The repo supports
  macOS, Linux, and WSL2 via platform-aware package driver."
applies_to_scope: "AI workstation setup — 9 governed components:
  software layer (software-bootstrap, dev-tools, docker, ai-python-stack,
  ai-apps), system layer (macos-config, system), verification (verify)"
decision_record_path: "./docs/bgs-decision.md"
inventory_path: "./README.md#repository-inventory"
orchestration_root: "./ucc/"
verification_root: "./tic/"
last_reviewed: 2026-04-02
last_validated: 2026-04-02
read_next:
  - "./README.md"
  - "./DRIVER_ARCHITECTURE.md"
  - "./docs/biss-classification.md"
  - "./docs/setup-state-model.md"
  - "./ucc/"
  - "./tools/validate_targets_manifest.py"
  - "./install.sh"
  - "./lib/ucc.sh"
  - "./lib/uic.sh"
  - "./lib/tic.sh"
  - "./tic/software/verify.yaml"
  - "./tic/system/verify.yaml"
  - "./tic/software/integration.yaml"
