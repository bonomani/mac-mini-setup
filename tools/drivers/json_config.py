#!/usr/bin/env python3
"""
tools/drivers/json_config.py  <check|read|apply> <file> [args...]

check  <file> <key>=<value> [<key2>=<value2>...]
         Exit 0 if all key-value pairs match, else exit 1

read   <file>
         Print current values as: key=value lines (one per top-level key)

apply  <file> <key>=<value> [<key2>=<value2>...]
         Update JSON file with provided key-value pairs (creates if absent)
"""
import json
import sys
import tempfile
import os
from pathlib import Path


def load_json(path: Path) -> dict:
    """Load JSON file, return empty dict on error."""
    try:
        text = path.read_text(encoding="utf-8")
        obj = json.loads(text)
        if not isinstance(obj, dict):
            return {}
        return obj
    except Exception:
        return {}


def check(settings_path: Path, patch: dict) -> int:
    """Check if all key-value pairs in patch match the settings file."""
    if not patch:
        return 0
    if not settings_path.exists():
        return 1
    settings = load_json(settings_path)
    for key, value in patch.items():
        if settings.get(key) != value:
            return 1
    return 0


def read(settings_path: Path) -> int:
    """Read JSON file and print key=value lines."""
    if not settings_path.exists():
        return 0
    data = load_json(settings_path)
    for key, value in sorted(data.items()):
        if isinstance(value, bool):
            print(f"{key}={str(value).lower()}")
        elif isinstance(value, (dict, list)):
            print(f"{key}={json.dumps(value)}")
        else:
            print(f"{key}={value}")
    return 0


def apply(settings_path: Path, patch: dict) -> int:
    """Merge patch into settings file."""
    settings = load_json(settings_path)
    if not isinstance(patch, dict):
        print(f"error: patch must be a JSON object", file=sys.stderr)
        return 1
    settings.update(patch)
    
    # Ensure parent directory exists
    settings_path.parent.mkdir(parents=True, exist_ok=True)
    
    # Write atomically using temp file
    tmp_fd, tmp_path = tempfile.mkstemp(dir=settings_path.parent, suffix=".tmp")
    try:
        with os.fdopen(tmp_fd, "w", encoding="utf-8") as fh:
            json.dump(settings, fh, indent=2, sort_keys=True)
            fh.write("\n")
        os.replace(tmp_path, settings_path)
    except Exception as exc:
        os.unlink(tmp_path)
        print(f"error: {exc}", file=sys.stderr)
        return 1
    return 0


def parse_patch_args(args: list[str]) -> dict:
    """Parse KEY=VALUE args into a dict."""
    result = {}
    for arg in args:
        if "=" not in arg:
            print(f"error: argument must be KEY=VALUE: {arg}", file=sys.stderr)
            return None
        key, value = arg.split("=", 1)
        # Try to parse the value as JSON (booleans, numbers, etc.)
        try:
            parsed = json.loads(value)
        except json.JSONDecodeError:
            # Keep as string
            parsed = value
        result[key] = parsed
    return result


def main() -> int:
    if len(sys.argv) < 3:
        print(f"usage: {sys.argv[0]} <check|read|apply> <file> [args...]", file=sys.stderr)
        return 2
    
    cmd = sys.argv[1]
    settings_path = Path(os.path.expanduser(sys.argv[2]))
    
    if cmd == "check":
        patch = parse_patch_args(sys.argv[3:]) or {}
        return check(settings_path, patch)
    
    elif cmd == "read":
        return read(settings_path)
    
    elif cmd == "apply":
        patch = parse_patch_args(sys.argv[3:]) or {}
        return apply(settings_path, patch)
    
    else:
        print(f"error: unknown command '{cmd}'", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())