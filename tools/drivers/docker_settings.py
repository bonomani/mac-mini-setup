#!/usr/bin/env python3
"""
tools/drivers/docker_settings.py  <read|apply>  <settings_file>  [args...]

read   <settings_file>
         Print current resource state as: mem=<N>GB cpu=<N>

apply  <settings_file>  <mem_mib>  <cpu_count>  <swap_mib>  <disk_mib>
         Update Docker settings file with new resource values.
"""
import json
import sys
import tempfile
import os
from pathlib import Path


def read(settings_path: Path) -> int:
    if not settings_path.exists():
        print("absent")
        return 0
    try:
        data = json.loads(settings_path.read_text(encoding="utf-8"))
    except Exception as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1
    mem_gb = int(data.get("memoryMiB", 0)) // 1024
    cpus = int(data.get("cpus", 0))
    print(f"mem={mem_gb}GB cpu={cpus}")
    return 0


def apply(settings_path: Path, mem_mib: int, cpu_count: int, swap_mib: int, disk_mib: int) -> int:
    if not settings_path.exists():
        print(f"error: settings file not found: {settings_path}", file=sys.stderr)
        return 1
    try:
        settings = json.loads(settings_path.read_text(encoding="utf-8"))
    except Exception as exc:
        print(f"error reading settings: {exc}", file=sys.stderr)
        return 1
    settings["memoryMiB"] = mem_mib
    settings["cpus"] = cpu_count
    settings["swapMiB"] = swap_mib
    settings["diskSizeMiB"] = disk_mib
    tmp_fd, tmp_path = tempfile.mkstemp(dir=settings_path.parent, suffix=".tmp")
    try:
        with os.fdopen(tmp_fd, "w", encoding="utf-8") as fh:
            json.dump(settings, fh, indent=2)
        os.replace(tmp_path, settings_path)
    except Exception as exc:
        os.unlink(tmp_path)
        print(f"error writing settings: {exc}", file=sys.stderr)
        return 1
    return 0


def main() -> int:
    if len(sys.argv) < 3:
        print(f"usage: {sys.argv[0]} <read|apply> <settings_file> [args...]", file=sys.stderr)
        return 2
    cmd = sys.argv[1]
    settings_path = Path(os.path.expanduser(sys.argv[2]))
    if cmd == "read":
        return read(settings_path)
    if cmd == "apply":
        if len(sys.argv) != 7:
            print(f"usage: {sys.argv[0]} apply <settings_file> <mem_mib> <cpu_count> <swap_mib> <disk_mib>", file=sys.stderr)
            return 2
        return apply(settings_path, int(sys.argv[3]), int(sys.argv[4]), int(sys.argv[5]), int(sys.argv[6]))
    print(f"error: unknown command '{cmd}'", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
