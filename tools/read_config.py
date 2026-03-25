#!/usr/bin/env python3
"""Read lists or records from simple YAML-like config files.

Usage:
  read_config.py --list <file> <section>
      Outputs each list item on its own line.

  read_config.py --records <file> <section> <field1> [field2 ...]
      Outputs tab-delimited records, one per list entry.
      Missing fields are output as empty strings.

  read_config.py --get <file> <key>
      Outputs a scalar value.  key may be a top-level key ("foo") or
      a two-level dotted path ("section.key") for nested mappings.
"""
import sys
from pathlib import Path


def read_list(path: Path, section: str) -> list:
    """Return items from a flat list section: `section:\\n  - item`."""
    items = []
    in_section = False
    for line in path.read_text().splitlines():
        s = line.rstrip()
        if not s or s.lstrip().startswith("#"):
            continue
        indent = len(s) - len(s.lstrip())
        text = s.strip()
        if indent == 0:
            in_section = text == f"{section}:"
            continue
        if in_section and indent == 2 and text.startswith("- "):
            val = text[2:]
            # Strip optional surrounding YAML quotes
            if len(val) >= 2 and val[0] == val[-1] and val[0] in ('"', "'"):
                val = val[1:-1]
            items.append(val)
    return items


def read_records(path: Path, section: str, fields: list) -> list:
    """Return records from a list-of-dicts section.

    Each record is a dict built from:
      - name: foo        <- first key of a list item (indent 2, starts with '- ')
        key: val         <- subsequent keys of the same item (indent 4)
    """
    records = []
    in_section = False
    current = None

    for line in path.read_text().splitlines():
        s = line.rstrip()
        if not s or s.lstrip().startswith("#"):
            continue
        indent = len(s) - len(s.lstrip())
        text = s.strip()

        if indent == 0:
            if in_section and current is not None:
                records.append(current)
            in_section = text == f"{section}:"
            current = None
            continue

        if not in_section:
            continue

        if indent == 2 and text.startswith("- "):
            if current is not None:
                records.append(current)
            current = {}
            rest = text[2:]
            if ":" in rest:
                k, v = rest.split(":", 1)
                v = v.strip()
                if len(v) >= 2 and v[0] == v[-1] and v[0] in ('"', "'"):
                    v = v[1:-1]
                current[k.strip()] = v
            continue

        if indent == 4 and current is not None and ":" in text:
            k, v = text.split(":", 1)
            v = v.strip()
            if len(v) >= 2 and v[0] == v[-1] and v[0] in ('"', "'"):
                v = v[1:-1]
            current[k.strip()] = v

    if in_section and current is not None:
        records.append(current)

    return ["\t".join(str(r.get(f, "")) for f in fields) for r in records]


def read_scalar(path: Path, key: str) -> str:
    """Return a scalar value from the config file.

    key may be:
      - "foo"           → top-level   foo: value
      - "section.key"   → two-level   section:\n  key: value  (indent 2)
    """
    parts = key.split(".", 1)
    if len(parts) == 1:
        # Top-level scalar
        for line in path.read_text().splitlines():
            s = line.rstrip()
            if not s or s.lstrip().startswith("#"):
                continue
            if len(s) - len(s.lstrip()) == 0 and ":" in s:
                k, v = s.split(":", 1)
                if k.strip() == parts[0]:
                    v = v.strip()
                    if len(v) >= 2 and v[0] == v[-1] and v[0] in ('"', "'"):
                        v = v[1:-1]
                    return v
    else:
        section, subkey = parts
        in_section = False
        for line in path.read_text().splitlines():
            s = line.rstrip()
            if not s or s.lstrip().startswith("#"):
                continue
            indent = len(s) - len(s.lstrip())
            text = s.strip()
            if indent == 0:
                in_section = text == f"{section}:"
                continue
            if in_section and indent == 2 and ":" in text:
                k, v = text.split(":", 1)
                if k.strip() == subkey:
                    v = v.strip()
                    if len(v) >= 2 and v[0] == v[-1] and v[0] in ('"', "'"):
                        v = v[1:-1]
                    return v
    return ""


def read_evidence(path: Path, target_name: str) -> list:
    """Return evidence key/cmd pairs for a target.

    Reads targets.<target>.evidence mapping and returns list of (key, cmd).
    Top-level scalar values are available for ${key} substitution in cmds.
    """
    import yaml as _yaml
    import re
    data = _yaml.safe_load(path.read_text()) or {}
    # Build substitution dict from top-level scalars
    subst = {k: str(v) for k, v in data.items()
             if isinstance(v, (str, int, float))}
    targets = data.get("targets") or {}
    target_data = targets.get(target_name) or {}
    evidence = target_data.get("evidence") or {}
    result = []
    for key, cmd in evidence.items():
        cmd = re.sub(r"\$\{(\w+)\}", lambda m: subst.get(m.group(1), m.group(0)), str(cmd))
        result.append(f"{key}\t{cmd}")
    return result


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
