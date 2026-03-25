# BGS Entry

project_name: mac-mini-setup
bgs_slice: BGS-State-Modeled-Governed
decision_reason: "AI workstation setup depends on explicit installation,
  configuration, readiness, runtime, and recovery semantics across 12
  interdependent components in two layers (software + system). Preflight
  gates and UCC convergence are interpreted against an ASM-aligned setup
  state model with parametric state for value-convergence targets; TIC
  verification remains additional evidence over the resulting state."
applies_to_scope: "Full Mac mini AI workstation setup — 12 components:
  software layer (homebrew, git, docker, python, ollama, ai-python-stack,
  ai-apps, dev-tools), system layer (git-config, docker-config,
  macos-defaults), verification (verify)"
decision_record_path: "./docs/bgs-decision.md"
last_reviewed: 2026-03-25
read_next:
  - "./docs/biss-classification.md"
  - "./docs/setup-state-model.md"
  - "./docs/setup-state-artifact.yaml"
  - "./ucc/"
  - "./tools/validate_targets_manifest.py"
  - "./install.sh"
  - "./lib/ucc.sh"
  - "./lib/uic.sh"
  - "./lib/tic.sh"
  - "./tic/software/verify.yaml"
  - "./tic/system/verify.yaml"
  - "./lib/tic_runner.sh"
  - "./lib/summary.sh"
  - "./docs/bgs-decision.md"
