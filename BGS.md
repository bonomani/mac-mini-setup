# BGS Entry

project_name: mac-mini-setup
bgs_slice: BGS-State-Modeled-Governed
decision_reason: "AI workstation setup depends on explicit installation,
  configuration, readiness, runtime, and recovery semantics across 10
  interdependent components. Preflight gates and UCC convergence are now
  interpreted against an ASM-aligned setup state model; TIC verification remains
  additional evidence over the resulting state."
applies_to_scope: "Full Mac mini AI workstation setup — all 10 components
  (homebrew, git, docker, python, ollama, ai-python-stack, ai-apps,
  dev-tools, macos-defaults, verify)"
decision_record_path: "./docs/bgs-decision.md"
last_reviewed: 2026-03-23
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
  - "./components/verify.sh"
  - "./docs/bgs-decision.md"
