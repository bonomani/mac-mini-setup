# BGS Entry

project_name: mac-mini-setup
bgs_slice: BGS-Governed-Verified
decision_reason: "AI workstation setup requires preflight gating (hardware/service
  readiness), declarative convergence (idempotent install/update), and explicit
  verification (post-install health checks) across 10 interdependent components."
applies_to_scope: "Full Mac mini AI workstation setup — all 10 components
  (homebrew, git, docker, python, ollama, ai-python-stack, ai-apps,
  dev-tools, macos-defaults, verify)"
decision_record_path: "./docs/bgs-decision.md"
last_reviewed: 2026-03-22
read_next:
  - "./install.sh"
  - "./lib/ucc.sh"
  - "./lib/uic.sh"
  - "./lib/tic.sh"
  - "./components/10-verify.sh"
  - "./docs/bgs-decision.md"
