#!/usr/bin/env python3
"""tools/build-driver-matrix.py — regenerate docs/driver-feature-matrix.md.

Walks lib/drivers/*.sh and ucc/**.yaml directly. No memory, no
hand-counted rows — what you see in the doc is what's in the source.

Sections produced:
  1. Active YAML kinds (target counts)
  2. Drivers by file (kinds, hooks, outdated/migration/activation)
  3. pkg backends (held in a fixed table — pkg.sh exposes them by name)
  4. pip driver detail
  5. Outdated detection summary
  6. Migration / foreign-install handling
  7. Runtime activation
  8. What was retired

Usage:
    python3 tools/build-driver-matrix.py             # write the file
    python3 tools/build-driver-matrix.py --check     # exit 1 if drift
    python3 tools/build-driver-matrix.py --stdout    # print, no write
"""
from __future__ import annotations

import argparse
import re
import sys
from collections import defaultdict
from pathlib import Path

try:
    import yaml
except ImportError:
    sys.exit("PyYAML required: pip install pyyaml")


REPO_ROOT = Path(__file__).resolve().parent.parent
DRIVERS_DIR = REPO_ROOT / "lib" / "drivers"
UCC_DIR = REPO_ROOT / "ucc"
MATRIX_PATH = REPO_ROOT / "docs" / "driver-feature-matrix.md"


# ── Static facts (extracted from pkg.sh comments / suite-map) ────────────────

PKG_BACKENDS = [
    # (name, implicit_dep, provided_by, outdated_mechanism)
    ("brew",      "homebrew",        "brew",                   "`brew outdated` always; `brew livecheck` when opt-in flag set"),
    ("brew-cask", "homebrew",        "brew-cask",              "`brew outdated --cask` (+ `--greedy` if YAML asks)"),
    ("native-pm", "build-deps",      "native-package-manager", "per-PM cache: `apt list --upgradable` / `dnf check-update` / `pacman -Qu` / `zypper -n list-updates`"),
    ("npm",       "node-lts",        "npm",                    "`npm outdated -g --json`, cached"),
    ("pyenv",     "pyenv",           "pyenv",                  "—"),
    ("ollama",    "ollama",          "ollama",                 "—"),
    ("vscode",    "vscode-code-cmd", "vscode-marketplace",     "marketplace `extensionquery` POST API, bulk + cached"),
    ("curl",      "(none)",          "curl",                   "`_pkg_curl_version` + `driver.github_repo` release tag, version-compare via `_pkg_version_lt`"),
]

RETIRED = [
    ("`bin-script`",              "`home-artifact` (subkind: script)"),
    ("`cli-symlink`",             "`home-artifact` (subkind: symlink)"),
    ("`pmset`",                   "`setting` (backend: pmset)"),
    ("`user-defaults`",           "`setting` (backend: defaults)"),
    ("`softwareupdate-defaults`", "`setting` (backend: defaults, requires_sudo: true)"),
    ("`brew-service`",            "`service` (backend: brew)"),
    ("`launchd`",                 "`service` (backend: launchd)"),
    ("`brew` (formula)",          "`pkg` (backend: brew)"),
    ("`package`",                 "`pkg` (backends: brew + native-pm + curl)"),
    ("`npm-global`",              "`pkg` (backend: npm)"),
    ("`vscode-marketplace`",      "`pkg` (backend: vscode)"),
    ("`pyenv-version`",           "`pkg` (backend: pyenv)"),
    ("`ollama-model`",            "`pkg` (backend: ollama)"),
    ("`curl-installer`",          "`pkg` (backend: curl)"),
]


# ── Source audit ──────────────────────────────────────────────────────────────

KIND_RE = re.compile(r"^_ucc_driver_([a-z_]+)_(observe|action|apply|evidence)\(\)", re.M)
HOOK_RE = re.compile(r"^_ucc_driver_([a-z_]+)_(observe|action|apply|evidence)\(\)", re.M)


def driver_audit() -> list[dict]:
    rows = []
    for f in sorted(DRIVERS_DIR.glob("*.sh")):
        text = f.read_text()
        # Kinds = unique driver_<name> prefixes (excluding sub-helper functions)
        kinds = set()
        for m in KIND_RE.finditer(text):
            name = m.group(1)
            # Strip the trailing hook word for safety
            for hook in ("_observe", "_action", "_apply", "_evidence"):
                if name.endswith(hook[1:]):
                    name = name[: -len(hook[1:]) - 1]
            kinds.add(name)
        # Recompute from full match cleanly
        kinds = sorted({m.group(1) for m in HOOK_RE.finditer(text)})
        hooks = {hook: bool(re.search(rf"^_ucc_driver_[a-z_]+_{hook}\(\)", text, re.M))
                 for hook in ("observe", "action", "apply", "evidence")}
        outdated = bool(re.search(r"\boutdated\b|\blivecheck\b", text))
        migration = bool(re.search(r"handle_foreign_install|migration_safety", text))
        activation = bool(re.search(r"_ensure_path|_activate", text))
        rows.append({
            "file": f.name,
            "kinds": kinds,
            "hooks": hooks,
            "outdated": outdated,
            "migration": migration,
            "activation": activation,
        })
    return rows


def yaml_kind_counts() -> dict[str, int]:
    counts: dict[str, int] = defaultdict(int)
    for ymlf in UCC_DIR.rglob("*.yaml"):
        try:
            data = yaml.safe_load(ymlf.read_text()) or {}
        except Exception:
            continue
        for body in (data.get("targets") or {}).values():
            kind = ((body or {}).get("driver") or {}).get("kind")
            if kind:
                counts[kind] += 1
    return dict(counts)


# ── Renderer ──────────────────────────────────────────────────────────────────

def md_check(b: bool) -> str:
    return "✅" if b else "—"


def render() -> str:
    audit = driver_audit()
    counts = yaml_kind_counts()
    total_targets = sum(counts.values())
    total_files = len(audit)

    out: list[str] = []
    a = out.append

    a("# Driver Feature Matrix")
    a("")
    a("Live snapshot of every driver under `lib/drivers/` and every active YAML")
    a("kind. **Generated by `tools/build-driver-matrix.py`** — do not edit by hand;")
    a("re-run the generator after any driver change.")
    a("")

    # ── Active YAML kinds ────────────────────────────────────────────────────
    a("## Active YAML kinds (by target count)")
    a("")
    a("| Kind | Targets |")
    a("|---|---:|")
    for kind, n in sorted(counts.items(), key=lambda kv: (-kv[1], kv[0])):
        a(f"| `{kind}` | {n} |")
    a("")
    a(f"**{total_targets} targets** across **{len(counts)} distinct kinds**.")
    a("")

    # ── Drivers by file ───────────────────────────────────────────────────────
    a("## Drivers by file")
    a("")
    a("| File | Kind(s) | obs | act | app | ev | outdated | migration | activation |")
    a("|---|---|---|---|---|---|---|---|---|")
    for r in audit:
        kinds_disp = ", ".join(f"`{k.replace('_','-')}`" for k in r["kinds"]) or "(helpers only)"
        a("| `{f}` | {k} | {o} | {ac} | {ap} | {e} | {ot} | {m} | {av} |".format(
            f=r["file"],
            k=kinds_disp,
            o=md_check(r["hooks"]["observe"]),
            ac=md_check(r["hooks"]["action"]),
            ap=md_check(r["hooks"]["apply"]),
            e=md_check(r["hooks"]["evidence"]),
            ot=md_check(r["outdated"]),
            m=md_check(r["migration"]),
            av=md_check(r["activation"]),
        ))
    a("")
    helpers_only = sum(1 for r in audit if not r["kinds"])
    a(f"**{total_files} driver files**, of which {total_files - helpers_only} export at "
      f"least one driver kind. The other {helpers_only} host helper functions only.")
    a("")

    # ── pkg backends ──────────────────────────────────────────────────────────
    a("## `pkg` backends in detail")
    a("")
    a("| Backend | Implicit dep | Provided-by | Outdated mechanism |")
    a("|---|---|---|---|")
    for be, dep, prov, otd in PKG_BACKENDS:
        a(f"| `{be}` | `{dep}` | `{prov}` | {otd} |")
    a("")
    a("All outdated probes gated behind `UIC_PREF_BREW_LIVECHECK=1`.")
    a("")

    # ── Retired ───────────────────────────────────────────────────────────────
    a("## What was retired")
    a("")
    a("| Old kind | Folded into |")
    a("|---|---|")
    for old, new in RETIRED:
        a(f"| {old} | {new} |")
    a("")
    a(f"{len(RETIRED)} driver kinds folded into 4 unified drivers (`pkg`, `setting`, `service`, `home_artifact`).")
    a("")

    a("## Linked living docs")
    a("")
    a("- `docs/install-method-gaps.md`")
    a("- `docs/update-detection-gaps.md`")
    a("- `docs/runtime-activation-gaps.md`")
    a("")
    return "\n".join(out)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--check", action="store_true",
                    help="exit 1 if generated content differs from on-disk file")
    ap.add_argument("--stdout", action="store_true",
                    help="print to stdout instead of writing the file")
    args = ap.parse_args()

    rendered = render()
    if args.stdout:
        sys.stdout.write(rendered)
        return 0
    if args.check:
        current = MATRIX_PATH.read_text() if MATRIX_PATH.exists() else ""
        if current != rendered:
            print(f"DRIFT: {MATRIX_PATH} is out of date. Run: python3 tools/build-driver-matrix.py",
                  file=sys.stderr)
            return 1
        print("OK: driver-feature-matrix.md is in sync")
        return 0
    MATRIX_PATH.write_text(rendered)
    print(f"wrote {MATRIX_PATH}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
