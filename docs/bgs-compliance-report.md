# BGS Compliance Report

Date: 2026-03-28
Project: `mac-mini-setup`
Claimed slice: `BGS-State-Modeled-Governed`
Assessment basis: repo-local artifacts, executable validators, and local runtime evidence

## Executive Summary

`mac-mini-setup` is materially compliant with its claimed `BGS-State-Modeled-Governed` slice based on the governance entry, decision record, BISS classification, ASM-aligned state model, executable validators, and available runtime UCC evidence present at review time.

This is a project-local compliance assessment, not an external audit or a claim about stronger rigor overlays such as `RIG`.

## Scope Reviewed

The assessed scope is the one declared in [`../BGS.md`](../BGS.md):

- AI workstation setup across 11 governed components
- full macOS profile
- portable Linux/WSL2 subset with unsupported components skipped by manifest scope and policy
- governed preflight, convergence, and post-convergence verification

## Reviewed Evidence

Primary governance and model artifacts:

- [`../BGS.md`](../BGS.md)
- [`bgs-decision.yaml`](./bgs-decision.yaml)
- [`biss-classification.md`](./biss-classification.md)
- [`setup-state-model.md`](./setup-state-model.md)
- [`setup-state-artifact.yaml`](./setup-state-artifact.yaml)

Executable and operational evidence:

- [`../tools/validate_setup_state_artifact.py`](../tools/validate_setup_state_artifact.py)
- [`../tools/validate_targets_manifest.py`](../tools/validate_targets_manifest.py)
- [`../install.sh`](../install.sh)
- [`../lib/ucc.sh`](../lib/ucc.sh)
- [`../lib/uic.sh`](../lib/uic.sh)
- [`../lib/tic.sh`](../lib/tic.sh)
- [`../tic/software/verify.yaml`](../tic/software/verify.yaml)
- [`../tic/system/verify.yaml`](../tic/system/verify.yaml)
- `~/.ai-stack/runs/*.declaration.jsonl`
- `~/.ai-stack/runs/*.result.jsonl`

## Validation Performed

The following checks were run during this review:

```bash
python3 tools/validate_setup_state_artifact.py docs/setup-state-artifact.yaml
python3 tools/validate_targets_manifest.py ucc
python3 tools/format_targets_manifest.py --check ucc
```

Observed results:

- ASM artifact validator: `VALID docs/setup-state-artifact.yaml`
- orchestration validator: `OK: 94 orchestration targets validated`
- manifest formatter check: pass
- runtime evidence present locally:
  - `4` declaration artifacts under `~/.ai-stack/runs/`
  - `4` result artifacts under `~/.ai-stack/runs/`

## Compliance Findings

### 1. Governance entry is present and specific

The repository contains a dedicated BGS project entry in [`../BGS.md`](../BGS.md) with:

- explicit slice selection
- declared scope
- decision record path
- orchestration and verification roots
- review and validation dates
- concrete next-read pointers

Status: compliant

### 2. Decision record is present and materially complete

The decision record in [`bgs-decision.yaml`](./bgs-decision.yaml) includes:

- pinned suite and member refs
- claimed members and overlay
- declared external controls
- evidence references
- explicit limitations

Status: compliant

### 3. BISS classification exists and matches the declared scope

The boundary classification in [`biss-classification.md`](./biss-classification.md) identifies:

- GCC at the preflight gate and preference layer
- UCC for convergence and reconciliation
- GIC for post-convergence verification

During the 2026-04-28 audit, the component count wording was re-aligned to the live UCC manifest tree: 11 governed components (9 software + 2 system). BGS, BISS, and ASM model docs now agree. `macos-software-update` is a target inside the `system` component, not a separate component.

Status: compliant

### 4. ASM-governed state evidence exists

The repo includes:

- a setup state model in [`setup-state-model.md`](./setup-state-model.md)
- a concrete state artifact in [`setup-state-artifact.yaml`](./setup-state-artifact.yaml)
- an executable validator in [`../tools/validate_setup_state_artifact.py`](../tools/validate_setup_state_artifact.py)

This supports the project’s claim that admissible convergence is interpreted against an explicit setup state model rather than only ad hoc installer behavior.

Status: compliant

### 5. UIC, UCC, and TIC are wired into the implementation

The implementation structure and inventory show:

- UIC preflight and preference handling through policy and shell libraries
- UCC declaration/result generation in the installer and runtime libraries
- TIC verification as read-only post-convergence evidence

This is consistent with the claimed slice and with the stated limitation that TIC evidence is not folded back into UCC state.

Status: compliant

## Residual Limits and Caveats

These do not invalidate the current slice claim, but they remain important:

- macOS is still the only full-profile target; Linux and WSL2 run a governed subset only
- TIC remains verification evidence, not convergence
- credentials, IAM, and most privacy controls are delegated to upstream tooling
- runtime evidence is partly outside the repository under `~/.ai-stack/runs/`
- some behavior remains policy-soft rather than hard-blocking, such as the sudo gate for `macos-defaults`
- the project claims the `Basic` overlay only, not `RIG`
- package targets use a project-local `state_model: package` mapping layered onto the ASM software profile
- externally managed updates and non-interactive admin-required targets remain project-local execution conventions rather than upstream suite-standardized semantics

## Verdict

As of 2026-03-28, `mac-mini-setup` is materially compliant with its declared `BGS-State-Modeled-Governed` slice on the basis of the reviewed artifacts and executed validators.

The current claim should still be read with the limitations above: this is a `Basic`-overlay, project-local compliance posture with explicit delegated controls and a macOS-first full profile.
