#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path

import yaml

from validate_targets_manifest import CANONICAL_TARGET_KEY_ORDER


def iter_yaml_files(path: Path):
    if path.is_file():
        if path.suffix in {".yaml", ".yml"}:
            yield path
        return
    for pattern in ("*.yaml", "*.yml"):
        yield from sorted(path.rglob(pattern))

DRIVER_KEY_ORDER = ["kind", "ref", "package_ref", "service_name", "app_name", "app_path", "domain", "key"]
ACTIONS_KEY_ORDER = ["install", "update"]
ENDPOINT_KEY_ORDER = ["name", "scheme", "host", "port", "path", "url", "note"]


def reorder_named_mapping(data: dict, ordered_keys: list[str]) -> dict:
    ordered = {}
    for key in ordered_keys:
        if key in data:
            ordered[key] = data[key]
    for key, value in data.items():
        if key not in ordered:
            ordered[key] = value
    return ordered


def reorder_target_mapping(target: dict) -> dict:
    ordered = {}
    for key in CANONICAL_TARGET_KEY_ORDER:
            if key in target:
                value = target[key]
                if key == "driver" and isinstance(value, dict):
                    value = reorder_named_mapping(value, DRIVER_KEY_ORDER)
                elif key == "actions" and isinstance(value, dict):
                    value = reorder_named_mapping(value, ACTIONS_KEY_ORDER)
                elif key == "endpoints" and isinstance(value, list):
                    value = [
                        reorder_named_mapping(endpoint, ENDPOINT_KEY_ORDER) if isinstance(endpoint, dict) else endpoint
                        for endpoint in value
                    ]
                ordered[key] = value
    for key, value in target.items():
        if key not in ordered:
            ordered[key] = value
    return ordered


def format_manifest_text(text: str) -> str:
    data = yaml.safe_load(text) or {}
    if not isinstance(data, dict):
        raise ValueError("manifest must contain a top-level mapping")

    targets = data.get("targets")
    if isinstance(targets, dict):
        reordered_targets = {}
        for name, target in targets.items():
            if isinstance(target, dict):
                reordered_targets[name] = reorder_target_mapping(target)
            else:
                reordered_targets[name] = target
        data = dict(data)
        data["targets"] = reordered_targets

    rendered = yaml.safe_dump(data, sort_keys=False, default_flow_style=False, allow_unicode=False)
    if not rendered.endswith("\n"):
        rendered += "\n"
    return rendered


def main() -> int:
    parser = argparse.ArgumentParser(description="Rewrite UCC target manifests to canonical key order.")
    parser.add_argument("paths", nargs="+", help="Manifest files or directories")
    parser.add_argument("--check", action="store_true", help="Fail if any file would be reformatted")
    args = parser.parse_args()

    changed = []
    for raw_path in args.paths:
        path = Path(raw_path)
        for file in iter_yaml_files(path):
            original = file.read_text(encoding="utf-8")
            formatted = format_manifest_text(original)
            if formatted != original:
                changed.append(file)
                if not args.check:
                    file.write_text(formatted, encoding="utf-8")

    if args.check and changed:
        for file in changed:
            print(file)
        return 1

    for file in changed:
        print(file)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
