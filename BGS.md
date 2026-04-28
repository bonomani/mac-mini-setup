# BGS Entry

project_name: mac-mini-setup
bgs_slice: BGS-State-Modeled-Governed
decision_reason: "AI workstation setup depends on explicit installation,
  configuration, readiness, runtime, and recovery semantics across 11
  components (9 software + 2 system, 11 active). Preflight gate
  (supported-platform) and UCC convergence are interpreted against an
  ASM-aligned setup state model with parametric state for value-convergence
  targets. Capability targets replace most gates for precondition checks.
  TIC verification provides post-convergence evidence. The repo supports
  macOS, Linux, and WSL2 via platform-aware package driver."
applies_to_scope: "AI workstation setup — 11 governed components (11 active):
  software layer (software-bootstrap, cli-tools, node-stack, vscode-stack,
  docker, ai-python-stack, ai-apps, build-tools, network-services),
  system layer (system, linux-system). Post-convergence TIC verification
  is run from `./tic/` but is not a separate governed component."
decision_record_path: "./docs/bgs-decision.yaml"
inventory_path: "./README.md#repository-inventory"
orchestration_root: "./ucc/"
verification_root: "./tic/"
last_reviewed: 2026-04-07
last_validated: 2026-04-07
bgs_version_ref: bgs@58c1467
bgs_canonical: ../BGSPrivate/bgs
read_next:
  - "./README.md"
  - "./DRIVER_ARCHITECTURE.md"
  - "./docs/biss-classification.md"
  - "./docs/setup-state-model.md"
  - "./ucc/"
  - "./tools/validate_targets_manifest.py"
  - "./tests/"
  - "./install.sh"
  - "./lib/ucc.sh"
  - "./lib/uic.sh"
  - "./lib/tic.sh"
  - "./tic/software/verify.yaml"
  - "./tic/system/verify.yaml"
  - "./tic/software/integration.yaml"
