# BGS Decision Record — mac-mini-setup

```yaml
decision_id: mac-mini-setup-bgs-001
bgs_slice: BGS-Governed-Verified
declared_scope: >
  Mac mini AI workstation setup — full installation lifecycle across 10
  components: homebrew, git, docker, python, ollama, ai-python-stack,
  ai-apps, dev-tools, macos-defaults, verify.
  Covers install, idempotent re-run, and update modes.

bgs_version_ref: bgs@c31f200

members_used:
  - BISS
  - UIC
  - UCC
  - TIC

overlays_used:
  - Basic

member_version_refs:
  UCC: ucc@1505204
  UIC: uic@a997340
  TIC: tic@5f125a3

external_controls:
  IAM and authorization: delegated
  # macOS user permissions and brew/npm/Docker Hub auth are handled by
  # the upstream toolchain. A sudo availability gate (UIC soft gate
  # 'sudo-available') guards components that require elevated privileges.
  sandboxing or runtime isolation: implemented
  # AI app services run in Docker containers (07-ai-apps).
  # Unsloth Studio runs in an isolated Python venv via launchd.
  # All launchd services are user-scoped (no root daemons).
  secret and token lifecycle: delegated
  # No secrets managed by this installer. Brew, Docker Hub, PyPI, and
  # npm use their own authentication. API keys are operator-supplied.
  rate limiting and budget control: implemented
  # Docker resource limits enforced: memory capped at 48 GB, CPU at 10
  # cores (03-docker.sh). Ollama model autopull defaults to 'none' to
  # prevent unintended bandwidth use (UIC preference ollama-model-autopull).
  privacy and data-boundary control: delegated
  # Network calls go to upstream registries (brew, PyPI, Docker Hub,
  # Ollama, npm). No telemetry is emitted by this installer. Brew
  # analytics are explicitly disabled (01-homebrew.sh).

evidence_refs:
  - ./install.sh          # UIC gates + preferences + orchestration
  - ./lib/ucc.sh          # UCC/2.0 engine (steps 0-6, result model, JSONL)
  - ./lib/uic.sh          # UIC preflight engine
  - ./lib/tic.sh          # TIC test engine
  - ./components/10-verify.sh   # 39 TIC tests covering all components
  - ~/.ai-stack/runs/     # Per-run UCC/2.0 JSONL result artifacts

limitations:
  - Does not claim privacy enforcement beyond disabling brew analytics;
    all network calls reach upstream public registries.
  - Does not manage credentials or API tokens.
  - TIC tests are read-only probes (GIC); they do not re-run convergence.
  - Sudo gate is soft (not hard); 09-macos-defaults is skipped if sudo
    is unavailable rather than aborting the full install.
```
