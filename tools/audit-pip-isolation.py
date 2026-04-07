#!/usr/bin/env python3
"""tools/audit-pip-isolation.py — read-only audit.

For every `kind: pip` target in ucc/, list each package in its
install_packages and report:
  - whether the package declares any console_scripts entry points
    (looked up via importlib.metadata in the *current* environment),
  - the script names if any.

Output is a hint table only. Never writes. Suggestion is per-package,
not per-group, because most groups mix CLI tools and libraries.

Usage:
    python3 tools/audit-pip-isolation.py [--json]
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

try:
    import yaml
except ImportError:
    sys.exit("PyYAML is required: pip install pyyaml")

try:
    from importlib.metadata import entry_points, PackageNotFoundError, distribution
except ImportError:
    sys.exit("Python 3.10+ required for importlib.metadata.entry_points group filter")


REPO_ROOT = Path(__file__).resolve().parent.parent
UCC_ROOT = REPO_ROOT / "ucc"


def strip_specifier(ref: str) -> str:
    """`langchain-core>=1.0.0` → `langchain-core`."""
    for sep in (">=", "<=", "==", "!=", ">", "<", "~="):
        if sep in ref:
            return ref.split(sep, 1)[0].strip()
    return ref.strip()


def find_pip_targets() -> list[tuple[str, str, dict]]:
    """Yield (yaml_path, target_name, target_dict) for every kind: pip target."""
    out: list[tuple[str, str, dict]] = []
    for yml in UCC_ROOT.rglob("*.yaml"):
        try:
            data = yaml.safe_load(yml.read_text()) or {}
        except Exception:
            continue
        targets = (data or {}).get("targets") or {}
        for name, body in targets.items():
            driver = (body or {}).get("driver") or {}
            if driver.get("kind") == "pip":
                out.append((str(yml.relative_to(REPO_ROOT)), name, body))
    return out


def package_console_scripts(pkg: str) -> list[str]:
    """Return entry-point names declared as console_scripts for <pkg>.

    Empty list = no CLI / not installed in this environment.
    """
    try:
        distribution(pkg)
    except PackageNotFoundError:
        return []
    eps = entry_points()
    try:
        cs = eps.select(group="console_scripts")
    except AttributeError:
        cs = eps.get("console_scripts", [])  # python <3.10 shape
    out = []
    for ep in cs:
        try:
            dist = getattr(ep, "dist", None)
            dist_name = (dist.metadata["Name"] if dist else "").lower()
        except Exception:
            dist_name = ""
        if dist_name == pkg.lower():
            out.append(ep.name)
    return sorted(set(out))


def audit(as_json: bool) -> int:
    targets = find_pip_targets()
    if not targets:
        print("no kind: pip targets found", file=sys.stderr)
        return 0

    report: list[dict] = []
    for yml, name, body in targets:
        driver = body.get("driver") or {}
        pkgs_field = (driver.get("install_packages") or "").strip()
        pkgs = [strip_specifier(p) for p in pkgs_field.split()] if pkgs_field else []
        target_report = {
            "yaml": yml,
            "target": name,
            "isolation": driver.get("isolation") or "none",
            "packages": [],
        }
        for pkg in pkgs:
            scripts = package_console_scripts(pkg)
            target_report["packages"].append({
                "name": pkg,
                "console_scripts": scripts,
                "candidate_for_pipx": bool(scripts),
            })
        report.append(target_report)

    if as_json:
        json.dump(report, sys.stdout, indent=2)
        sys.stdout.write("\n")
        return 0

    for tr in report:
        any_cli = any(p["candidate_for_pipx"] for p in tr["packages"])
        marker = "→ has CLI tools" if any_cli else "  (library-only)"
        print(f"{tr['target']}  [isolation={tr['isolation']}]  {marker}")
        print(f"  yaml: {tr['yaml']}")
        for p in tr["packages"]:
            if p["console_scripts"]:
                scripts = ", ".join(p["console_scripts"])
                print(f"    {p['name']:30s}  CLI: {scripts}")
            elif distribution_present(p["name"]):
                print(f"    {p['name']:30s}  (library)")
            else:
                print(f"    {p['name']:30s}  (not installed in this env — skipped)")
        print()
    return 0


def distribution_present(pkg: str) -> bool:
    try:
        distribution(pkg)
        return True
    except PackageNotFoundError:
        return False


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--json", action="store_true", help="emit JSON instead of text")
    args = ap.parse_args()
    return audit(args.json)


if __name__ == "__main__":
    sys.exit(main())
