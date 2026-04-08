#!/usr/bin/env python3
"""tools/build-spec.py — regenerate docs/SPEC.md from source.

Reverse-engineers the project's current behavior by walking the
source files. Produces a single doc that stays in sync with code.

Sources:
  - BGS.md                      → identity, slice, scope
  - docs/bgs-decision.yaml      → members, version refs, external controls
  - defaults/selection.yaml     → component layout, globally-disabled targets
  - defaults/preferences.yaml   → UIC preferences
  - defaults/gates.yaml         → UIC gates
  - ucc/**/*.yaml               → every target with kind/type/display_name/...
  - tic/**/*.yaml               → every TIC verification test
  - install.sh                  → CLI surface (parsed from usage())
  - tools/validate_targets_manifest.py → driver schema reference (link only)

Hand-editable: a `<!-- GOAL-BEGIN ... GOAL-END -->` block is preserved
between regenerations. Edit the goal there; the generator never touches
what's between the markers.

Modes:
  python3 tools/build-spec.py            # write the file
  python3 tools/build-spec.py --check    # exit 1 on drift
  python3 tools/build-spec.py --stdout   # print only
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
SPEC_PATH = REPO_ROOT / "docs" / "SPEC.md"

GOAL_PLACEHOLDER = (
    "_(Edit me — describe the project's goal in plain language. "
    "Everything between the GOAL-BEGIN and GOAL-END markers is "
    "preserved across regenerations.)_"
)


# ── Source readers ────────────────────────────────────────────────────────────

def read_bgs_entry() -> dict:
    """Parse BGS.md frontmatter-style key: value lines."""
    text = (REPO_ROOT / "BGS.md").read_text()
    out: dict = {}
    cur_key = None
    for line in text.splitlines():
        if line.startswith("#"):
            continue
        # Continuation of multi-line value
        if cur_key and line.startswith(("  ", "\t")):
            out[cur_key] = (out[cur_key] or "") + " " + line.strip()
            continue
        m = re.match(r"^([a-z_][a-z_0-9]*):\s*(.*)$", line)
        if m:
            cur_key, val = m.group(1), m.group(2).strip().strip('"\'')
            out[cur_key] = val
    return out


def read_decision() -> dict:
    p = REPO_ROOT / "docs" / "bgs-decision.yaml"
    if not p.exists():
        return {}
    try:
        return yaml.safe_load(p.read_text()) or {}
    except Exception:
        return {}


def read_selection() -> dict:
    p = REPO_ROOT / "defaults" / "selection.yaml"
    return yaml.safe_load(p.read_text()) or {}


def read_preferences() -> list:
    p = REPO_ROOT / "defaults" / "preferences.yaml"
    return (yaml.safe_load(p.read_text()) or {}).get("preferences") or []


def read_gates() -> list:
    p = REPO_ROOT / "defaults" / "gates.yaml"
    return (yaml.safe_load(p.read_text()) or {}).get("gates") or []


def read_ucc_targets() -> list[tuple[str, str, dict]]:
    """(component_yaml_path, target_name, target_dict) for every target."""
    out: list[tuple[str, str, dict]] = []
    for ymlf in sorted((REPO_ROOT / "ucc").rglob("*.yaml")):
        try:
            data = yaml.safe_load(ymlf.read_text()) or {}
        except Exception:
            continue
        comp = data.get("component") or ymlf.stem
        for name, body in (data.get("targets") or {}).items():
            out.append((comp, name, body or {}))
    return out


def read_tic_tests() -> list[dict]:
    """Every test from tic/**/*.yaml."""
    out: list[dict] = []
    for ymlf in sorted((REPO_ROOT / "tic").rglob("*.yaml")):
        try:
            data = yaml.safe_load(ymlf.read_text()) or {}
        except Exception:
            continue
        for t in data.get("tests") or []:
            out.append(t)
    return out


def read_cli_usage() -> list[str]:
    """Extract option lines from install.sh usage() heredoc."""
    text = (REPO_ROOT / "install.sh").read_text()
    m = re.search(r"^usage\(\)\s*\{[^\n]*\n(.*?)^\}", text, re.S | re.M)
    if not m:
        return []
    body = m.group(1)
    opts: list[str] = []
    for line in body.splitlines():
        s = line.strip()
        if s.startswith("--") or re.match(r"^-[a-zA-Z],", s):
            opts.append(s)
    return opts


# ── Goal block preservation ───────────────────────────────────────────────────

GOAL_RE = re.compile(
    r"<!-- GOAL-BEGIN -->.*?<!-- GOAL-END -->",
    re.DOTALL,
)


def preserved_goal_block() -> str:
    if not SPEC_PATH.exists():
        return f"<!-- GOAL-BEGIN -->\n{GOAL_PLACEHOLDER}\n<!-- GOAL-END -->"
    text = SPEC_PATH.read_text()
    m = GOAL_RE.search(text)
    if m:
        return m.group(0)
    return f"<!-- GOAL-BEGIN -->\n{GOAL_PLACEHOLDER}\n<!-- GOAL-END -->"


# ── Renderer ──────────────────────────────────────────────────────────────────

def render() -> str:
    bgs = read_bgs_entry()
    decision = read_decision()
    selection = read_selection()
    prefs = read_preferences()
    gates = read_gates()
    targets = read_ucc_targets()
    tic_tests = read_tic_tests()
    cli_opts = read_cli_usage()

    by_component: dict[str, list] = defaultdict(list)
    kind_counts: dict[str, int] = defaultdict(int)
    for comp, name, body in targets:
        by_component[comp].append((name, body))
        kind = ((body.get("driver") or {}).get("kind")) or "(none)"
        kind_counts[kind] += 1

    out: list[str] = []
    a = out.append

    a("# SPEC")
    a("")
    a("Reverse-engineered live specification of `mac-mini-setup`.")
    a("**Generated by `tools/build-spec.py`** — do not edit by hand")
    a("(except the GOAL block below). Re-run the generator after any")
    a("source change.")
    a("")

    # ── 1. Identity & goal ───────────────────────────────────────────────────
    a("## 1. Identity & goal")
    a("")
    a(f"- **Project**: `{bgs.get('project_name', '?')}`")
    a(f"- **BGS slice**: `{bgs.get('bgs_slice', '?')}`")
    if bgs.get("bgs_version_ref"):
        a(f"- **BGS version ref**: `{bgs['bgs_version_ref']}`")
    if bgs.get("decision_record_path"):
        a(f"- **Decision record**: [`{bgs['decision_record_path']}`]({bgs['decision_record_path']})")
    if bgs.get("last_reviewed"):
        a(f"- **Last reviewed**: {bgs['last_reviewed']}")
    a("")
    a("### Goal (hand-editable)")
    a("")
    a(preserved_goal_block())
    a("")
    if bgs.get("decision_reason"):
        a("### Decision reason (from BGS.md)")
        a("")
        a(f"> {bgs['decision_reason']}")
        a("")
    if bgs.get("applies_to_scope"):
        a("### Scope (from BGS.md)")
        a("")
        a(f"> {bgs['applies_to_scope']}")
        a("")

    # ── 2. Architecture ──────────────────────────────────────────────────────
    a("## 2. Architecture")
    a("")
    a("```")
    a("install.sh")
    a("  └─ UIC pre-convergence  → gates + preference resolution (lib/uic.sh)")
    a("  └─ UCC convergence      → component runners + driver dispatch (lib/ucc*.sh, lib/drivers/*.sh)")
    a("  └─ TIC verification     → post-convergence assertions (lib/tic*.sh, tic/**.yaml)")
    a("```")
    a("")
    a("The driver layer is the single dispatch point for installs/upgrades/")
    a("config writes. See `docs/driver-feature-matrix.md` for the full list.")
    a("")

    # ── 3. Components ────────────────────────────────────────────────────────
    a("## 3. Components")
    a("")
    a("Component order from `defaults/selection.yaml` (or YAML alpha order if")
    a("not specified). Counts are real (`type` distribution per component).")
    a("")
    a("| Component | Targets | type=package | type=config | type=runtime | type=capability |")
    a("|---|---:|---:|---:|---:|---:|")
    for comp in sorted(by_component.keys()):
        rows = by_component[comp]
        types = defaultdict(int)
        for _, body in rows:
            types[body.get("type") or "(none)"] += 1
        a(f"| `{comp}` | {len(rows)} | {types['package']} | {types['config']} | {types['runtime']} | {types['capability']} |")
    a("")
    if selection.get("disabled"):
        a("**Globally disabled** (in `defaults/selection.yaml`):")
        a("")
        for d in sorted(selection["disabled"]):
            a(f"- `{d}`")
        a("")

    # ── 4. Targets by component ──────────────────────────────────────────────
    a("## 4. Targets by component")
    a("")
    for comp in sorted(by_component.keys()):
        rows = sorted(by_component[comp], key=lambda r: r[0])
        a(f"### {comp}  ({len(rows)} targets)")
        a("")
        a("| Target | Kind | Type | Display name | requires | depends_on |")
        a("|---|---|---|---|---|---|")
        for name, body in rows:
            kind = ((body.get("driver") or {}).get("kind")) or "—"
            typ = body.get("type") or "—"
            disp = (body.get("display_name") or "").replace("|", "\\|")
            req = body.get("requires") or ""
            deps = body.get("depends_on") or []
            if isinstance(deps, list):
                deps_disp = ", ".join(f"`{d}`" for d in deps[:3])
                if len(deps) > 3:
                    deps_disp += f" (+{len(deps) - 3})"
            else:
                deps_disp = ""
            a(f"| `{name}` | `{kind}` | `{typ}` | {disp} | {req} | {deps_disp} |")
        a("")

    # ── 5. Preferences ───────────────────────────────────────────────────────
    a("## 5. Preferences  (`defaults/preferences.yaml`)")
    a("")
    a("| Name | Default | Options | Rationale |")
    a("|---|---|---|---|")
    for p in prefs:
        name = p.get("name", "")
        default = str(p.get("default", ""))
        options = p.get("options", "")
        rationale = (p.get("rationale") or "").replace("|", "\\|")
        a(f"| `{name}` | `{default}` | `{options}` | {rationale} |")
    a("")

    # ── 6. Gates ─────────────────────────────────────────────────────────────
    a("## 6. Gates  (`defaults/gates.yaml`)")
    a("")
    a("| Name | Class | Scope | Condition |")
    a("|---|---|---|---|")
    for g in gates:
        a("| `{n}` | `{c}` | `{s}` | `{cd}` |".format(
            n=g.get("name", ""),
            c=g.get("class", ""),
            s=g.get("scope", ""),
            cd=g.get("condition", ""),
        ))
    a("")

    # ── 7. CLI surface ───────────────────────────────────────────────────────
    a("## 7. CLI surface  (`install.sh`)")
    a("")
    a("Parsed from `install.sh:usage()`:")
    a("")
    a("```")
    for line in cli_opts:
        a(line)
    a("```")
    a("")

    # ── 8. BGS claim ─────────────────────────────────────────────────────────
    a("## 8. BGS compliance claim")
    a("")
    a(f"- **Slice**: `{decision.get('bgs_slice', '?')}`")
    a(f"- **Decision ID**: `{decision.get('decision_id', '?')}`")
    members = decision.get("members_used") or []
    if members:
        a(f"- **Members used**: {', '.join('`'+m+'`' for m in members)}")
    overlays = decision.get("overlays_used") or []
    if overlays:
        a(f"- **Overlays used**: {', '.join('`'+m+'`' for m in overlays)}")
    profiles = decision.get("profiles") or []
    if profiles:
        a(f"- **Profiles**: {', '.join('`'+p+'`' for p in profiles)}")
    refs = decision.get("member_version_refs") or {}
    if refs:
        a("- **Immutable member refs**:")
        for k, v in sorted(refs.items()):
            a(f"  - `{k}: {v}`")
    ext = decision.get("external_controls") or {}
    if ext:
        a("- **External controls**:")
        for k, v in sorted(ext.items()):
            a(f"  - `{k}` → `{v}`")
    a("")
    a("Validate with: `tools/check-bgs.sh`")
    a("")

    # ── 9. Verification ──────────────────────────────────────────────────────
    a("## 9. TIC verification catalog")
    a("")
    a(f"{len(tic_tests)} post-convergence tests across `tic/`.")
    a("")
    a("| Name | Component | Intent | Oracle |")
    a("|---|---|---|---|")
    for t in tic_tests:
        intent = (t.get("intent") or "").replace("|", "\\|")
        oracle = (t.get("oracle") or "").replace("|", "\\|").replace("`", "")
        if len(oracle) > 60:
            oracle = oracle[:57] + "..."
        a("| `{n}` | `{c}` | {i} | `{o}` |".format(
            n=t.get("name", ""),
            c=t.get("component", ""),
            i=intent,
            o=oracle,
        ))
    a("")

    # ── 10. Driver inventory ─────────────────────────────────────────────────
    a("## 10. Driver inventory")
    a("")
    a("See [`docs/driver-feature-matrix.md`](driver-feature-matrix.md) — auto-generated by `tools/build-driver-matrix.py`.")
    a("")

    # ── 11. Counts ───────────────────────────────────────────────────────────
    a("## 11. Counts (live)")
    a("")
    a(f"- Components: **{len(by_component)}**")
    a(f"- Targets: **{len(targets)}**")
    a(f"- Distinct driver kinds: **{len(kind_counts)}**")
    a(f"- Preferences: **{len(prefs)}**")
    a(f"- Gates: **{len(gates)}**")
    a(f"- TIC tests: **{len(tic_tests)}**")
    a(f"- Globally disabled targets: **{len((selection.get('disabled') or []))}**")
    a("")
    a("Top 10 driver kinds by target count:")
    a("")
    a("| Kind | Targets |")
    a("|---|---:|")
    for k, n in sorted(kind_counts.items(), key=lambda kv: (-kv[1], kv[0]))[:10]:
        a(f"| `{k}` | {n} |")
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
        current = SPEC_PATH.read_text() if SPEC_PATH.exists() else ""
        if current != rendered:
            print(f"DRIFT: {SPEC_PATH} is out of date. Run: python3 tools/build-spec.py",
                  file=sys.stderr)
            return 1
        print(f"OK: {SPEC_PATH.name} is in sync")
        return 0
    SPEC_PATH.write_text(rendered)
    print(f"wrote {SPEC_PATH}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
