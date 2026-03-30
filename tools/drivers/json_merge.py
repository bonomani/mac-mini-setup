#!/usr/bin/env python3
"""
tools/drivers/json_merge.py  <check|apply>  <settings_json>  <patch_json>

check  - exit 0 if all patch keys exist in settings with matching values, else 1
apply  - merge patch into settings file (creates settings file if absent)
"""
import json
import sys
import tempfile
import os
from pathlib import Path


def load_json(path: Path) -> dict:
    try:
        text = path.read_text(encoding="utf-8")
        obj = json.loads(text)
        if not isinstance(obj, dict):
            return {}
        return obj
    except Exception:
        return {}


def check(settings_path: Path, patch_path: Path) -> int:
    patch = load_json(patch_path)
    if not patch:
        return 0
    if not settings_path.exists():
        return 1
    settings = load_json(settings_path)
    for key, value in patch.items():
        if settings.get(key) != value:
            return 1
    return 0


def apply(settings_path: Path, patch_path: Path) -> int:
    patch = load_json(patch_path)
    if not isinstance(patch, dict):
        print(f"error: patch file is not a JSON object: {patch_path}", file=sys.stderr)
        return 1
    settings: dict = {}
    if settings_path.exists():
        settings = load_json(settings_path)
    settings.update(patch)
    settings_path.parent.mkdir(parents=True, exist_ok=True)
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


def main() -> int:
    if len(sys.argv) != 4:
        print(f"usage: {sys.argv[0]} <check|apply> <settings_json> <patch_json>", file=sys.stderr)
        return 2
    cmd = sys.argv[1]
    settings_path = Path(sys.argv[2])
    patch_path = Path(sys.argv[3])
    if cmd == "check":
        return check(settings_path, patch_path)
    if cmd == "apply":
        return apply(settings_path, patch_path)
    print(f"error: unknown command '{cmd}'", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
