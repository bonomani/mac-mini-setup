# BISS Classification: mac-mini-setup

Scope:
- Mac mini AI workstation setup — full installation lifecycle across 10 components

Boundary inventory:

| Boundary interaction | Crosses | Axis A | Axis B | Rationale |
| --- | --- | --- | --- | --- |
| Preflight gate and preference resolution | operator/policy layer -> local setup controller | GCC | Basic | Preflight resolves gates and preferences before any convergence occurs. It produces an explicit opposable decision layer, but it does not itself reconcile the workstation into the desired end state. |
| Component convergence and package/service setup | local setup controller -> local filesystem, package managers, launchd, Docker daemon, and macOS system APIs | UCC | Basic | Each setup step declares a target state, observes the current state, computes the difference, applies the transition, and records a UCC declaration/result artifact. |
| Post-convergence verification probes | local setup controller -> installed binaries, local HTTP endpoints, launchd state, and container health endpoints | GIC | Basic | Verification checks observe the resulting system state and report pass/fail without mutating the target system. |

Classification notes:
- The setup scope includes governed preflight, convergence, and read-only verification within one declared BGS slice.
- `Basic` is the claimed rigor overlay for this project; it does not claim `RIG`.
- Network calls to upstream package registries are part of the UCC execution boundary, not separate BGS claim members.
