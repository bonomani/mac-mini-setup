# BGS Entry

project_name: mac-mini-setup
bgs_slice: BGS-State-Modeled-Governed
decision_reason: "AI workstation setup depends on explicit installation,
  configuration, readiness, runtime, and recovery semantics across 14
  interdependent components in two layers (software + system). Preflight
  gates and UCC convergence are interpreted against an ASM-aligned setup
  state model with parametric state for value-convergence targets; TIC
  verification remains additional evidence over the resulting state. The
  repo is macOS-first, but portable subsets can run on Linux and WSL with
  unsupported components skipped by policy and manifest platform scope."
applies_to_scope: "AI workstation setup — 14 governed components with a
  full macOS profile and a portable Linux/WSL subset:
  software layer (homebrew, git, docker, python, ollama, ai-python-stack,
  ai-apps, dev-tools), system layer (git-config, docker-config,
  macos-software-update, macos-defaults, system), verification (verify)"
decision_record_path: "./docs/bgs-decision.md"
inventory_path: "./README.md#repository-inventory"
orchestration_root: "./ucc/"
verification_root: "./tic/"
last_reviewed: 2026-03-28
last_validated: 2026-03-28
read_next:
  - "./README.md"
  - "./docs/biss-classification.md"
  - "./docs/setup-state-model.md"
  - "./docs/setup-state-artifact.yaml"
  - "./ucc/"
  - "./tools/validate_targets_manifest.py"
  - "./tools/validate_setup_state_artifact.py"
  - "./install.sh"
  - "./lib/ucc.sh"
  - "./lib/uic.sh"
  - "./lib/tic.sh"
  - "./tic/software/verify.yaml"
  - "./tic/system/verify.yaml"
  - "./lib/tic_runner.sh"
  - "./lib/summary.sh"
