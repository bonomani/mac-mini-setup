#!/usr/bin/env python3
from __future__ import annotations

"""Split --all-targets-get-many-with-evidence output into per-target shell export statements.

Usage: split_yaml_batch.py <yaml_fn>

Reads line-oriented batch data from stdin (key\tbase64(value) lines with
__target__\tname separators). Outputs one shell export statement per target:

  export _UCC_YTGT_<yaml_fn>_<target_fn>='<base64(NUL-delimited rows)>'

The exported value is base64 of the NUL-delimited scalar+evidence rows for that
target, identical to what --target-get-many-with-evidence produces. Setup
functions decode it with base64 -d and read the NUL-delimited stream directly.
"""
import sys
import base64
import re


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__, file=sys.stderr)
        return 1

    yaml_fn = sys.argv[1]
    current_target: str | None = None
    current_rows = b""

    def flush(target_fn: str, rows: bytes) -> None:
        b64 = base64.b64encode(rows).decode("ascii")
        print(f"export _UCC_YTGT_{yaml_fn}_{target_fn}={b64!r}")

    for line in sys.stdin:
        line = line.rstrip("\n")
        if not line:
            continue
        if line.startswith("__target__\t"):
            if current_target is not None:
                flush(current_target, current_rows)
            raw_name = line[len("__target__\t"):]
            current_target = re.sub(r"[^a-zA-Z0-9]", "_", raw_name)
            current_rows = b""
            continue
        if current_target is None:
            continue
        tab = line.index("\t")
        key = line[:tab]
        b64val = line[tab + 1:]
        value = base64.b64decode(b64val)
        if key == "__evidence__":
            current_rows += b"__evidence__\t" + b64val.encode("ascii") + b"\0"
        else:
            current_rows += f"{key}\t".encode("utf-8") + value + b"\0"

    if current_target is not None:
        flush(current_target, current_rows)

    return 0


if __name__ == "__main__":
    sys.exit(main())
