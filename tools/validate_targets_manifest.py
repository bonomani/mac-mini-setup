#!/usr/bin/env python3
import sys
from collections import defaultdict
from pathlib import Path


KNOWN_PROFILES = {"presence", "configured", "runtime", "verification"}
KNOWN_GATES = {
    "macos-platform",
    "apple-silicon",
    "docker-daemon",
    "docker-settings-file",
    "ollama-api",
    "sudo-available",
}


def parse_manifest(path: Path):
    targets = {}
    current = None
    current_list = None
    in_targets = False

    for lineno, raw in enumerate(path.read_text().splitlines(), start=1):
        if not raw.strip() or raw.lstrip().startswith("#"):
            continue
        if raw.rstrip() != raw:
            raw = raw.rstrip()
        indent = len(raw) - len(raw.lstrip(" "))
        text = raw.strip()

        if indent == 0:
            if text != "targets:":
                raise ValueError(f"{path}:{lineno}: expected 'targets:'")
            in_targets = True
            continue

        if not in_targets:
            raise ValueError(f"{path}:{lineno}: content before 'targets:'")

        if indent == 2 and text.endswith(":"):
            current = text[:-1]
            targets[current] = {}
            current_list = None
            continue

        if current is None:
            raise ValueError(f"{path}:{lineno}: field without target")

        if indent == 4 and text.endswith(":"):
            key = text[:-1]
            if key not in {"depends_on", "soft_depends_on"}:
                raise ValueError(f"{path}:{lineno}: unsupported list field '{key}'")
            targets[current][key] = []
            current_list = key
            continue

        if indent == 4 and ":" in text:
            key, value = text.split(":", 1)
            targets[current][key.strip()] = value.strip()
            current_list = None
            continue

        if indent == 6 and text.startswith("- "):
            if current_list is None:
                raise ValueError(f"{path}:{lineno}: list item without active list")
            targets[current][current_list].append(text[2:].strip())
            continue

        raise ValueError(f"{path}:{lineno}: unsupported structure")

    return targets


def validate(targets):
    errors = []

    for name, data in targets.items():
        profile = data.get("profile")
        component = data.get("component")
        if not profile:
            errors.append(f"target '{name}' missing profile")
        elif profile not in KNOWN_PROFILES:
            errors.append(f"target '{name}' has unknown profile '{profile}'")
        if not component:
            errors.append(f"target '{name}' missing component")

        for dep in data.get("depends_on", []):
            if dep not in targets:
                errors.append(f"target '{name}' depends_on unknown target '{dep}'")

        for dep in data.get("soft_depends_on", []):
            if dep.startswith("gate:"):
                gate = dep.split(":", 1)[1]
                if gate not in KNOWN_GATES:
                    errors.append(f"target '{name}' soft_depends_on unknown gate '{gate}'")
            elif dep not in targets:
                errors.append(f"target '{name}' soft_depends_on unknown target '{dep}'")

    graph = defaultdict(list)
    indegree = {name: 0 for name in targets}
    for name, data in targets.items():
        for dep in data.get("depends_on", []):
            graph[dep].append(name)
            indegree[name] += 1

    queue = [name for name, degree in indegree.items() if degree == 0]
    ordered = []
    while queue:
        node = queue.pop(0)
        ordered.append(node)
        for child in graph[node]:
            indegree[child] -= 1
            if indegree[child] == 0:
                queue.append(child)

    if len(ordered) != len(targets):
        remaining = sorted(name for name, degree in indegree.items() if degree > 0)
        errors.append(f"dependency cycle detected among: {', '.join(remaining)}")

    return errors, ordered


def main():
    args = sys.argv[1:]
    deps_mode = False
    target_name = None
    if len(args) >= 2 and args[0] == "--deps":
        deps_mode = True
        target_name = args[1]
        args = args[2:]

    path = Path(args[0]) if args else Path("targets.yaml")
    try:
        targets = parse_manifest(path)
        errors, ordered = validate(targets)
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    if errors:
        for error in errors:
            print(f"ERROR: {error}", file=sys.stderr)
        return 1

    if deps_mode:
        for dep in targets.get(target_name, {}).get("depends_on", []):
            print(dep)
        return 0

    print(f"OK: {len(targets)} orchestration targets validated")
    print("Topological order:")
    for name in ordered:
        print(f"  - {name}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
