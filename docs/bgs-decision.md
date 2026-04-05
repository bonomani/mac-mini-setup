# BGS Decision Record — mac-mini-setup

```yaml
decision_id: mac-mini-setup-bgs-001
bgs_slice: BGS-State-Modeled-Governed
declared_scope: >
  AI workstation setup — full installation lifecycle across 10
  governed components (10 active). macOS is the primary/full
  profile; Linux and WSL2 run most components via the platform-aware
  package driver with macOS-specific targets skipped:
  software layer (ucc/software/): software-bootstrap, cli-tools,
  node-stack, vscode-stack, docker, ai-python-stack, ai-apps,
  build-tools);
  system layer (ucc/system/): system, system;
  verification (tic/): verify + integration.
  Covers install, check (drift detection), update, and interactive modes.

bgs_version_ref: bgs@6d9b3d8

members_used:
  - BISS
  - ASM
  - UIC
  - UCC
  - TIC

overlays_used:
  - Basic

external_controls:
  IAM and authorization: delegated
  # macOS user permissions and brew/npm/Docker Hub auth are handled by
  # the upstream toolchain. Targets requiring sudo use a capability
  # target (sudo-available) and admin_required metadata; operators
  # may pre-acquire a sudo ticket with `sudo -v` or run as root.
  # Privilege elevation uses `run_elevated` helper which skips sudo
  # when EUID=0 (already root) and uses `sudo` otherwise.
  # `sudo_is_available` checks EUID=0 OR cached sudo ticket.
  # All sudo calls are guarded — no interactive password prompt.
  sandboxing or runtime isolation: implemented
  # AI app services run in Docker containers (ai-apps).
  # Unsloth Studio runs in an isolated Python venv via launchd/systemd.
  secret and token lifecycle: delegated
  # No secrets managed by this installer.
  rate limiting and budget control: implemented
  # Docker resource limits enforced via parametric target.
  # Ollama model autopull defaults to 'none' (UIC preference).
  # AI apps image policy defaults to 'reuse-local'.
  privacy and data-boundary control: delegated
  # Network calls go to upstream registries. No telemetry emitted.
  # Brew analytics explicitly disabled.

evidence_refs:
  - ./biss-classification.md
  - ./setup-state-model.md
  - ./setup-state-artifact.yaml
  - ../DRIVER_ARCHITECTURE.md
  - ../tools/validate_targets_manifest.py
  - ../install.sh
  - ../lib/ucc.sh
  - ../lib/uic.sh
  - ../policy/gates.yaml
  - ../policy/preferences.yaml
  - ../lib/tic.sh
  - ../tic/software/verify.yaml
  - ../tic/system/verify.yaml
  - ../tic/software/integration.yaml
  - ../lib/tic_runner.sh
  - ../lib/summary.sh

limitations:
  - macOS remains the full-profile target. Linux/WSL2 run most software
    targets via the package driver; macOS-only components (system,
    docker, system) are skipped on non-macOS platforms.
  - Does not manage credentials or API tokens.
  - TIC tests are read-only probes; they do not re-run convergence.
  - Sudo availability is a capability target; admin targets cascade-fail
    gracefully when no non-interactive sudo ticket exists.
  - The repo uses project-local package specialization on the ASM
    software profile (state_model: package).
  - The claimed BGS slice is BGS-State-Modeled-Governed; TIC is used
    as additional verification evidence.
```
