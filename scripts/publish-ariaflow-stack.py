#!/usr/bin/env python3
from __future__ import annotations

import argparse
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
WORKSPACE = ROOT.parent
ARIAFLOW = WORKSPACE / "ariaflow"
ARIAFLOW_WEB = WORKSPACE / "ariaflow-web"


def run(repo_name: str, repo_path: Path, subcommand: str, version: str | None, no_tests: bool) -> None:
    if not repo_path.exists():
        raise SystemExit(f"Missing repo path for {repo_name}: {repo_path}")

    cmd = ["python3", "scripts/publish.py", subcommand]
    if version is not None:
        cmd.extend(["--version", version])
    if no_tests:
        cmd.append("--no-tests")
    if subcommand == "plan":
        cmd.append("--allow-dirty")

    print(f"==> {repo_name}: {' '.join(cmd)}", flush=True)
    subprocess.run(cmd, cwd=repo_path, check=True)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Rebase-safe double-publish helper for ariaflow and ariaflow-web."
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    plan_parser = subparsers.add_parser("plan", help="Preview the commands that would run in both repos.")
    plan_parser.add_argument("--no-tests", action="store_true", help="Show a plan that skips local tests in both repos.")
    plan_parser.add_argument("--ariaflow-version", help="Preview an explicit stable release version for ariaflow.")
    plan_parser.add_argument("--ariaflow-web-version", help="Preview an explicit stable release version for ariaflow-web.")

    push_parser = subparsers.add_parser("push", help="Push main in both repos with rebase-safe sync.")
    push_parser.add_argument("--no-tests", action="store_true", help="Skip local tests in both repos.")

    release_parser = subparsers.add_parser("release", help="Trigger explicit release flow for one or both repos after rebase-safe sync.")
    release_parser.add_argument("--no-tests", action="store_true", help="Skip local tests in both repos.")
    release_parser.add_argument("--ariaflow-version", help="Explicit stable release version for ariaflow.")
    release_parser.add_argument("--ariaflow-web-version", help="Explicit stable release version for ariaflow-web.")

    args = parser.parse_args()

    ariaflow_version = getattr(args, "ariaflow_version", None)
    ariaflow_web_version = getattr(args, "ariaflow_web_version", None)

    if args.command == "release" and not ariaflow_version and not ariaflow_web_version:
        raise SystemExit("Pass at least one explicit version for the release command.")

    ariaflow_command = args.command
    ariaflow_web_command = args.command
    if args.command == "release" and ariaflow_version is None:
        ariaflow_command = "push"
    if args.command == "release" and ariaflow_web_version is None:
        ariaflow_web_command = "push"

    run(
        repo_name="ariaflow",
        repo_path=ARIAFLOW,
        subcommand=ariaflow_command,
        version=ariaflow_version,
        no_tests=args.no_tests,
    )
    run(
        repo_name="ariaflow-web",
        repo_path=ARIAFLOW_WEB,
        subcommand=ariaflow_web_command,
        version=ariaflow_web_version,
        no_tests=args.no_tests,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
