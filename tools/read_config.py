#!/usr/bin/env python3
"""Read lists, records, scalars, or evidence from YAML config files.

Usage:
  read_config.py --list <file> <section>
      Outputs each list item on its own line.

  read_config.py --records <file> <section> <field1> [field2 ...]
      Outputs tab-delimited records, one per list entry.
      Missing fields are output as empty strings.

  read_config.py --get <file> <key>
      Outputs a scalar value. key may be a dotted path such as
      "section.key" or "section.nested.key".

  read_config.py --evidence <file> <target>
      Outputs tab-delimited evidence key/command pairs for a target.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

import yaml


def load_yaml(path: Path):
    data = yaml.safe_load(path.read_text()) or {}
    if not isinstance(data, dict):
        raise ValueError(f"{path} must contain a top-level mapping")
    return data


def get_path(data: dict, dotted_key: str):
    current = data
    for part in dotted_key.split("."):
        if not isinstance(current, dict) or part not in current:
            return ""
        current = current[part]
    return current


def stringify(value) -> str:
    if value is None:
        return ""
    if isinstance(value, bool):
        return "true" if value else "false"
    return str(value)


def read_list(path: Path, section: str) -> list[str]:
    data = load_yaml(path)
    value = get_path(data, section)
    if value in ("", None):
        return []
    if not isinstance(value, list):
        raise ValueError(f"section '{section}' is not a list")
    return [stringify(item) for item in value]


def read_records(path: Path, section: str, fields: list[str]) -> list[str]:
    data = load_yaml(path)
    value = get_path(data, section)
    if value in ("", None):
        return []
    if not isinstance(value, list):
        raise ValueError(f"section '{section}' is not a list of mappings")

    rows = []
    for index, item in enumerate(value):
        if not isinstance(item, dict):
            raise ValueError(f"section '{section}' entry {index} is not a mapping")
        rows.append("\t".join(stringify(item.get(field, "")) for field in fields))
    return rows


def read_scalar(path: Path, key: str) -> str:
    data = load_yaml(path)
    value = get_path(data, key)
    if isinstance(value, (dict, list)):
        return ""
    return stringify(value)


def read_evidence(path: Path, target_name: str) -> list[str]:
    data = load_yaml(path)
    subst = {
        key: stringify(value)
        for key, value in data.items()
        if isinstance(value, (str, int, float, bool))
    }
    targets = data.get("targets") or {}
    if not isinstance(targets, dict):
        raise ValueError("top-level 'targets' must be a mapping")
    target_data = targets.get(target_name) or {}
    if not isinstance(target_data, dict):
        return []
    evidence = target_data.get("evidence") or {}
    if not isinstance(evidence, dict):
        raise ValueError(f"target '{target_name}' evidence must be a mapping")

    rows = []
    for key, cmd in evidence.items():
        rendered = re.sub(r"\$\{(\w+)\}", lambda m: subst.get(m.group(1), m.group(0)), stringify(cmd))
        rows.append(f"{key}\t{rendered}")
    return rows


def main() -> int:
    args = sys.argv[1:]
    if not args:
        print(__doc__, file=sys.stderr)
        return 1

    mode = args[0]

    if mode == "--evidence":
        if len(args) < 3:
            print("Usage: read_config.py --evidence <file> <target>", file=sys.stderr)
            return 1
        path = Path(args[1])
        if not path.exists():
            return 0
        try:
            for row in read_evidence(path, args[2]):
                print(row)
        except Exception as exc:
            print(f"ERROR: {exc}", file=sys.stderr)
            return 1
        return 0

    if mode == "--get":
        if len(args) < 3:
            print(__doc__, file=sys.stderr)
            return 1
        path = Path(args[1])
        key = args[2]
        if not path.exists():
            print(f"ERROR: {path} not found", file=sys.stderr)
            return 1
        try:
            print(read_scalar(path, key))
        except Exception as exc:
            print(f"ERROR: {exc}", file=sys.stderr)
            return 1
        return 0

    if len(args) < 3:
        print(__doc__, file=sys.stderr)
        return 1

    path = Path(args[1])
    section = args[2]
    fields = args[3:]

    if not path.exists():
        print(f"ERROR: {path} not found", file=sys.stderr)
        return 1

    try:
        if mode == "--list":
            for item in read_list(path, section):
                print(item)
        elif mode == "--records":
            if not fields:
                print("ERROR: --records requires at least one field name", file=sys.stderr)
                return 1
            for row in read_records(path, section, fields):
                print(row)
        else:
            print(f"ERROR: unknown mode '{mode}'", file=sys.stderr)
            return 1
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
