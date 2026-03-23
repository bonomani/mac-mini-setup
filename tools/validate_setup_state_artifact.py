#!/usr/bin/env python3
from __future__ import annotations

import json
import subprocess
import sys
import tempfile
from pathlib import Path


def parse_scalar(value: str):
    value = value.strip()
    if value.startswith('"') and value.endswith('"'):
        return value[1:-1]
    return value


def load_simple_yaml(path: Path) -> dict:
    data: dict[str, object] = {}
    current_list_key: str | None = None
    current_map_key: str | None = None
    for raw_line in path.read_text().splitlines():
        line = raw_line.rstrip()
        if not line or line.lstrip().startswith("#"):
            continue
        if line.startswith("  - ") and current_list_key:
            data.setdefault(current_list_key, [])
            assert isinstance(data[current_list_key], list)
            data[current_list_key].append(parse_scalar(line[4:]))
            continue
        if line.startswith("  ") and current_map_key and ":" in line:
            sub_key, sub_value = line.strip().split(":", 1)
            data.setdefault(current_map_key, {})
            assert isinstance(data[current_map_key], dict)
            data[current_map_key][sub_key.strip()] = parse_scalar(sub_value)
            continue
        current_list_key = None
        current_map_key = None
        key, value = line.split(":", 1)
        key = key.strip()
        value = value.strip()
        if value == "":
            # list or mapping starts on following lines
            if key in {"derived_states", "notes"}:
                data[key] = []
                current_list_key = key
            else:
                data[key] = {}
                current_map_key = key
        else:
            data[key] = parse_scalar(value)
    return data


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: validate_setup_state_artifact.py <artifact.yaml>", file=sys.stderr)
        return 2

    artifact_path = Path(sys.argv[1]).resolve()
    repo_root = Path(__file__).resolve().parents[1]
    validator = repo_root.parent / "asm" / "tools" / "validate_software_state.py"

    state = load_simple_yaml(artifact_path)
    allowed_keys = {
        "profile_layer",
        "installation_state",
        "runtime_state",
        "health_state",
        "admin_state",
        "dependency_state",
        "derived_states",
        "last_transition",
    }
    state_payload = {k: v for k, v in state.items() if k in allowed_keys}

    with tempfile.NamedTemporaryFile("w+", suffix=".json", delete=False) as tmp:
        tmp.write(json.dumps(state_payload))
        tmp_path = Path(tmp.name)

    proc = subprocess.run(
        [sys.executable, str(validator), str(tmp_path)],
        text=True,
        capture_output=True,
    )
    try:
        tmp_path.unlink(missing_ok=True)
    except Exception:
        pass
    if proc.returncode == 0:
      print(f"VALID {artifact_path}")
      return 0

    sys.stderr.write(proc.stderr or proc.stdout or "validation failed\n")
    return proc.returncode


if __name__ == "__main__":
    raise SystemExit(main())
