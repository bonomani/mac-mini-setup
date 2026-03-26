# BGS Decision Record — mac-mini-setup

```yaml
decision_id: mac-mini-setup-bgs-001
bgs_slice: BGS-State-Modeled-Governed
declared_scope: >
  Mac mini AI workstation setup — full installation lifecycle across 13
  components in two layers:
  software layer (ucc/software/): homebrew, git, docker, python, ollama,
  ai-python-stack, ai-apps, dev-tools;
  system layer (ucc/system/): git-config, docker-config, macos-defaults, system;
  verification (tic/): verify.
  Covers install, idempotent re-run, and update modes.

bgs_version_ref: bgs@7961fb4

members_used:
  - BISS
  - ASM
  - UIC
  - UCC
  - TIC

overlays_used:
  - Basic

member_version_refs:
  asm: asm@dca032b
  # BISS is hosted in the UCC repo and is pinned through the same ref.
  ucc: ucc@370c1f7
  uic: uic@11bd400
  tic: tic@7cfba80

external_controls:
  IAM and authorization: delegated
  # macOS user permissions and brew/npm/Docker Hub auth are handled by
  # the upstream toolchain. A sudo availability gate (UIC soft gate
  # 'sudo-available') guards components that require elevated privileges.
  sandboxing or runtime isolation: implemented
  # AI app services run in Docker containers (ai-apps).
  # Unsloth Studio runs in an isolated Python venv via launchd.
  # All launchd services are user-scoped (no root daemons).
  secret and token lifecycle: delegated
  # No secrets managed by this installer. Brew, Docker Hub, PyPI, and
  # npm use their own authentication. API keys are operator-supplied.
  rate limiting and budget control: implemented
  # Docker resource limits enforced: memory capped at 48 GB, CPU at 10
  # cores (docker.sh). Ollama model autopull defaults to 'none' to
  # prevent unintended bandwidth use (UIC preference ollama-model-autopull).
  # AI apps image refresh policy defaults to 'reuse-local' to avoid
  # unnecessary image pulls during stack startup/update.
  privacy and data-boundary control: delegated
  # Network calls go to upstream registries (brew, PyPI, Docker Hub,
  # Ollama, npm). No telemetry is emitted by this installer. Brew
  # analytics are explicitly disabled (homebrew.sh).

evidence_refs:
  - ./biss-classification.md     # explicit BISS boundary inventory for this scope
  - ./setup-state-model.md       # ASM-aligned setup state model
  - ./setup-state-artifact.yaml  # concrete state artifact
  - ../tools/validate_setup_state_artifact.py  # executable ASM artifact validator
  - ./evidence/ollama-service.declaration.json
  - ./evidence/ollama-service.result.json
  - ../install.sh                # orchestration entry point
  - ../lib/ucc.sh                # UCC/2.0 declaration/result artifact engine
  - ../lib/uic.sh                # UIC preflight engine
  - ../policy/gates.yaml         # includes stack-specific ai-apps preflight gates
  - ../policy/preferences.yaml   # includes stack-specific image pull policy
  - ../lib/tic.sh                # TIC test engine
  - ../tic/software/verify.yaml  # TIC software-layer test definitions
  - ../tic/system/verify.yaml    # TIC system-layer test definitions
  - ../stack/docker-compose.yml  # stack definition template for ai-apps
  - ../lib/ai_apps.sh            # stack convergence logic and definition/runtime checks
  - ../lib/system.sh             # system-level composition target over governed subsystems
  - ../ucc/system/system.yaml    # system composition declaration
  - ../lib/tic_runner.sh          # TIC runner (run_verify sources the above YAML files)
  - ../lib/summary.sh            # final summary rendering
  - ~/.ai-stack/runs/*.declaration.jsonl  # runtime evidence outside the repo
  - ~/.ai-stack/runs/*.result.jsonl       # runtime evidence outside the repo

limitations:
  - Does not claim privacy enforcement beyond disabling brew analytics;
    all network calls reach upstream public registries.
  - Does not manage credentials or API tokens.
  - TIC tests are read-only probes (GIC); they do not re-run convergence.
  - Stack governance is currently project-local: ai-apps uses a
    parametric stack-definition target, stack-specific UIC gates, and
    TIC endpoint checks, but these semantics are not yet generalized in
    the upstream suite members.
  - Sudo gate is soft (not hard); macos-defaults is skipped if sudo
    is unavailable rather than aborting the full install.
  - The claimed BGS slice is `BGS-State-Modeled-Governed`; `TIC` is used
    as additional verification evidence because the suite does not yet
    define a separate state-modeled-governed-verified slice.
```
