# PLAN

(empty — see git log for completed work)

## Open

### Phase X1 — New backends: `mise`, `nix`, `aur`  (open-ended)

Not blocking any current target. Add when a real use case appears.

- `mise`: `mise install <pkg>@<ver>`, `mise outdated`. Single-ref.
  Easy fit for the `pkg` backend pattern.
- `nix`: nixpkgs flake refs. Needs `nix profile install` and
  `nix profile diff-closures` for outdated. Medium effort.
- `aur`: `paru -S <pkg>`. Linux-only. Single-ref. Easy fit.

Each new backend is its own commit; do them as need arises.
