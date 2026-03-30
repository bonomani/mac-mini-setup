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

  read_config.py --get-many <file> <key1> [key2 ...]
      Outputs NUL-delimited tab-separated key/value rows for top-level scalar lookups.

  read_config.py --target-get <file> <target> <key>
      Outputs a scalar value from a named target mapping.

  read_config.py --target-get-many <file> <target> <key1> [key2 ...]
      Outputs NUL-delimited tab-separated key/value rows for scalar lookups in one target.

  read_config.py --evidence <file> <target>
      Outputs NUL-delimited tab-separated evidence key/command pairs for a target.
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


def collect_scalars(value, out: dict[str, str], prefix: str = "") -> None:
    if isinstance(value, dict):
        for key, raw in value.items():
            if not isinstance(key, str) or not key:
                continue
            nested = f"{prefix}.{key}" if prefix else key
            collect_scalars(raw, out, nested)
        return
    if prefix and isinstance(value, (str, int, float, bool)):
        out[prefix] = stringify(value)


def substitute_scalars(value: str, data: dict) -> str:
    subst = dict(data)
    return re.sub(r"\$\{([A-Za-z0-9_.]+)\}", lambda m: subst.get(m.group(1), m.group(0)), value)


def top_level_scalars(data: dict) -> dict:
    scalars: dict[str, str] = {}
    for key, raw in data.items():
        if key == "targets":
            continue
        collect_scalars(raw, scalars, key)
    return scalars


def target_scalars(data: dict, target_name: str) -> dict:
    merged = top_level_scalars(data)
    targets = data.get("targets") or {}
    target = targets.get(target_name) or {}
    if isinstance(target, dict):
        for key, raw in target.items():
            collect_scalars(raw, merged, key)
    return merged


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
        rendered = []
        for field in fields:
            raw = item.get(field, "")
            value = stringify(raw)
            if isinstance(raw, str):
                value = substitute_scalars(value, top_level_scalars(data))
            rendered.append(value)
        rows.append("\t".join(rendered))
    return rows


def read_target_scalar(path: Path, target_name: str, key: str) -> str:
    data = load_yaml(path)
    targets = data.get("targets") or {}
    if not isinstance(targets, dict):
        raise ValueError("top-level 'targets' must be a mapping")
    target = targets.get(target_name)
    if not isinstance(target, dict):
        return ""
    value = get_path(target, key)
    if isinstance(value, (dict, list)):
        return ""
    rendered = stringify(value)
    if isinstance(value, str):
        rendered = substitute_scalars(rendered, target_scalars(data, target_name))
    return rendered


def read_scalar(path: Path, key: str) -> str:
    data = load_yaml(path)
    value = get_path(data, key)
    if isinstance(value, (dict, list)):
        return ""
    rendered = stringify(value)
    if isinstance(value, str):
        rendered = substitute_scalars(rendered, top_level_scalars(data))
    return rendered


def read_scalars(path: Path, keys: list[str]) -> list[str]:
    data = load_yaml(path)
    scalars = top_level_scalars(data)
    rows = []
    for key in keys:
        value = get_path(data, key)
        if isinstance(value, (dict, list)):
            rendered = ""
        else:
            rendered = stringify(value)
            if isinstance(value, str):
                rendered = substitute_scalars(rendered, scalars)
        rows.append(f"{key}\t{rendered}")
    return rows


def read_target_scalars(path: Path, target_name: str, keys: list[str]) -> list[str]:
    data = load_yaml(path)
    targets = data.get("targets") or {}
    if not isinstance(targets, dict):
        raise ValueError("top-level 'targets' must be a mapping")
    target = targets.get(target_name)
    if not isinstance(target, dict):
        return [f"{key}\t" for key in keys]

    scalars = target_scalars(data, target_name)
    rows = []
    for key in keys:
        value = get_path(target, key)
        if isinstance(value, (dict, list)):
            rendered = ""
        else:
            rendered = stringify(value)
            if isinstance(value, str):
                rendered = substitute_scalars(rendered, scalars)
        rows.append(f"{key}\t{rendered}")
    return rows


def print_nul_rows(rows: list[str]) -> None:
    stream = sys.stdout.buffer
    for row in rows:
        stream.write(row.encode("utf-8"))
        stream.write(b"\0")


def read_target_scalars_with_evidence(path: Path, target_name: str, keys: list[str]) -> tuple[list[str], str]:
    """Return (scalar_rows, evidence_b64) in one YAML parse.

    evidence_b64 is the base64 encoding of the NUL-delimited evidence rows,
    matching exactly what --evidence | base64 would produce. Bash stores it
    as a plain string without NUL-byte issues.
    """
    import base64
    data = load_yaml(path)
    targets = data.get("targets") or {}
    if not isinstance(targets, dict):
        raise ValueError("top-level 'targets' must be a mapping")
    target = targets.get(target_name)
    scalars = target_scalars(data, target_name)

    scalar_rows = []
    if not isinstance(target, dict):
        scalar_rows = [f"{key}\t" for key in keys]
    else:
        for key in keys:
            value = get_path(target, key)
            if isinstance(value, (dict, list)):
                rendered = ""
            else:
                rendered = stringify(value)
                if isinstance(value, str):
                    rendered = substitute_scalars(rendered, scalars)
            scalar_rows.append(f"{key}\t{rendered}")

    ev_bytes = b""
    if isinstance(target, dict):
        evidence = target.get("evidence") or {}
        if isinstance(evidence, dict):
            for key, cmd in evidence.items():
                rendered = substitute_scalars(stringify(cmd), scalars)
                ev_bytes += f"{key}\t{rendered}".encode("utf-8") + b"\0"

    return scalar_rows, base64.b64encode(ev_bytes).decode("ascii")


def read_evidence(path: Path, target_name: str) -> list[str]:
    data = load_yaml(path)
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
    scalars = target_scalars(data, target_name)
    for key, cmd in evidence.items():
        rendered = substitute_scalars(stringify(cmd), scalars)
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
            print_nul_rows(read_evidence(path, args[2]))
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

    if mode == "--get-many":
        if len(args) < 3:
            print("Usage: read_config.py --get-many <file> <key1> [key2 ...]", file=sys.stderr)
            return 1
        path = Path(args[1])
        if not path.exists():
            print(f"ERROR: {path} not found", file=sys.stderr)
            return 1
        try:
            print_nul_rows(read_scalars(path, args[2:]))
        except Exception as exc:
            print(f"ERROR: {exc}", file=sys.stderr)
            return 1
        return 0

    if mode == "--target-get":
        if len(args) < 4:
            print("Usage: read_config.py --target-get <file> <target> <key>", file=sys.stderr)
            return 1
        path = Path(args[1])
        if not path.exists():
            print(f"ERROR: {path} not found", file=sys.stderr)
            return 1
        try:
            print(read_target_scalar(path, args[2], args[3]))
        except Exception as exc:
            print(f"ERROR: {exc}", file=sys.stderr)
            return 1
        return 0

    if mode == "--target-get-many":
        if len(args) < 4:
            print("Usage: read_config.py --target-get-many <file> <target> <key1> [key2 ...]", file=sys.stderr)
            return 1
        path = Path(args[1])
        if not path.exists():
            print(f"ERROR: {path} not found", file=sys.stderr)
            return 1
        try:
            print_nul_rows(read_target_scalars(path, args[2], args[3:]))
        except Exception as exc:
            print(f"ERROR: {exc}", file=sys.stderr)
            return 1
        return 0

    if mode == "--target-get-many-with-evidence":
        if len(args) < 4:
            print("Usage: read_config.py --target-get-many-with-evidence <file> <target> <key1> [key2 ...]", file=sys.stderr)
            return 1
        path = Path(args[1])
        if not path.exists():
            print(f"ERROR: {path} not found", file=sys.stderr)
            return 1
        try:
            scalar_rows, evidence_b64 = read_target_scalars_with_evidence(path, args[2], args[3:])
            print_nul_rows(scalar_rows)
            print_nul_rows([f"__evidence__\t{evidence_b64}"])
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
