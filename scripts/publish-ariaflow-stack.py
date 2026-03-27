#!/usr/bin/env python3
from __future__ import annotations

import argparse
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
WORKSPACE = ROOT.parent
ARIAFLOW = WORKSPACE / "ariaflow"
ARIAFLOW_WEB = WORKSPACE / "ariaflow-web"


def run(repo_name: str, repo_path: Path, version: str | None, push: bool, dry_run: bool, no_tests: bool) -> None:
    if not repo_path.exists():
        raise SystemExit(f"Missing repo path for {repo_name}: {repo_path}")

    cmd = ["python3", "scripts/publish.py"]
    if version is not None:
        cmd.extend(["--version", version])
    if no_tests:
        cmd.append("--no-tests")
    if dry_run:
        cmd.extend(["--dry-run", "--allow-dirty"])
    if push:
        cmd.append("--push")

    print(f"==> {repo_name}: {' '.join(cmd)}", flush=True)
    subprocess.run(cmd, cwd=repo_path, check=True)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Rebase-safe double-publish helper for ariaflow and ariaflow-web."
    )
    parser.add_argument("--push", action="store_true", help="Push main in both repos. Required for real publish actions.")
    parser.add_argument("--dry-run", action="store_true", help="Preview the commands that would run in both repos.")
    parser.add_argument("--no-tests", action="store_true", help="Skip local tests in both repos.")
    parser.add_argument("--ariaflow-version", help="Explicit stable release version for ariaflow.")
    parser.add_argument("--ariaflow-web-version", help="Explicit stable release version for ariaflow-web.")
    args = parser.parse_args()

    if not args.dry_run and not args.push:
        raise SystemExit("Pass --push for real actions, or --dry-run to preview them.")

    run(
        repo_name="ariaflow",
        repo_path=ARIAFLOW,
        version=args.ariaflow_version,
        push=args.push,
        dry_run=args.dry_run,
        no_tests=args.no_tests,
    )
    run(
        repo_name="ariaflow-web",
        repo_path=ARIAFLOW_WEB,
        version=args.ariaflow_web_version,
        push=args.push,
        dry_run=args.dry_run,
        no_tests=args.no_tests,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
