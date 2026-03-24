#!/usr/bin/env python3
import sys
from collections import defaultdict
from pathlib import Path


KNOWN_PROFILES = {"presence", "configured", "runtime", "verification"}
KNOWN_TARGET_TYPES = {
    "package",
    "config",
    "runtime",
    "precondition",
    "service",
}


def parse_gate_names(path: Path):
    gate_names = set()
    if not path.exists():
        return gate_names

    for lineno, raw in enumerate(path.read_text().splitlines(), start=1):
        if not raw.strip() or raw.lstrip().startswith("#"):
            continue
        if raw.startswith("  - name: "):
            gate_names.add(raw[len("  - name: "):].strip())
        elif raw.startswith("gates:") or raw.startswith("    ") or raw.startswith("  "):
            continue
        else:
            raise ValueError(f"{path}:{lineno}: unsupported gate manifest structure")

    return gate_names

def parse_manifest_file(path: Path):
    manifest = {"component": None, "primary_profile": None, "targets": {}}
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
            if text == "targets:":
                in_targets = True
                continue
            if ":" in text:
                key, value = text.split(":", 1)
                key = key.strip()
                value = value.strip()
                _ALLOWED_TOP_LEVEL = {
                    "component", "primary_profile",
                    # dispatch fields (used by install.sh dynamic runner)
                    "libs", "runner", "on_fail",
                    # version/config fields (single source of truth)
                    "python_version", "node_version", "node_previous_version",
                    "macos_min_version", "installer_url", "api_host", "api_port", "log_file",
                    "omz_theme", "omz_installer_url", "ariaflow_tap", "aria2_port", "ariaflow_web_port",
                    "memory_gb", "cpu_count", "swap_mib", "disk_mib",
                }
                if key not in _ALLOWED_TOP_LEVEL:
                    raise ValueError(f"{path}:{lineno}: unsupported top-level field '{key}'")
                manifest[key] = value
                continue
            raise ValueError(f"{path}:{lineno}: unsupported top-level structure")

        if not in_targets:
            raise ValueError(f"{path}:{lineno}: content before 'targets:'")

        if indent == 2 and text.endswith(":"):
            current = text[:-1]
            manifest["targets"][current] = {}
            current_list = None
            continue

        if current is None:
            raise ValueError(f"{path}:{lineno}: field without target")

        if indent == 4 and text.endswith(":"):
            key = text[:-1]
            if key not in {"depends_on", "soft_depends_on"}:
                raise ValueError(f"{path}:{lineno}: unsupported list field '{key}'")
            manifest["targets"][current][key] = []
            current_list = key
            continue

        if indent == 4 and ":" in text:
            key, value = text.split(":", 1)
            manifest["targets"][current][key.strip()] = value.strip()
            current_list = None
            continue

        if indent == 6 and text.startswith("- "):
            if current_list is None:
                raise ValueError(f"{path}:{lineno}: list item without active list")
            manifest["targets"][current][current_list].append(text[2:].strip())
            continue

        raise ValueError(f"{path}:{lineno}: unsupported structure")

    return manifest


def parse_manifest(path: Path):
    if path.is_dir():
        merged = {"targets": {}, "components": {}}
        files = sorted(path.glob("*.yaml"))
        if not files:
            raise ValueError(f"{path}: no *.yaml files found")
        for file in files:
            manifest = parse_manifest_file(file)
            component = manifest.get("component")
            if component:
                if component in merged["components"]:
                    raise ValueError(f"{file}: duplicate component '{component}'")
                merged["components"][component] = {
                    "primary_profile": manifest.get("primary_profile", ""),
                    "libs": manifest.get("libs", ""),
                    "runner": manifest.get("runner", ""),
                    "on_fail": manifest.get("on_fail", ""),
                    "file": str(file),
                }
            for name, data in manifest["targets"].items():
                if name in merged["targets"]:
                    raise ValueError(f"{file}: duplicate target '{name}'")
                merged["targets"][name] = data
        return merged
    manifest = parse_manifest_file(path)
    return {"targets": manifest["targets"], "components": {}}


def validate(manifest, known_gates):
    targets = manifest["targets"]
    components = manifest["components"]
    errors = []

    for name, data in targets.items():
        profile = data.get("profile")
        target_type = data.get("type")
        component = data.get("component")
        if not profile:
            errors.append(f"target '{name}' missing profile")
        elif profile not in KNOWN_PROFILES:
            errors.append(f"target '{name}' has unknown profile '{profile}'")
        if not target_type:
            errors.append(f"target '{name}' missing type")
        elif target_type not in KNOWN_TARGET_TYPES:
            errors.append(f"target '{name}' has unknown type '{target_type}'")
        if not component:
            errors.append(f"target '{name}' missing component")

        for dep in data.get("depends_on", []):
            if dep not in targets:
                errors.append(f"target '{name}' depends_on unknown target '{dep}'")

        for dep in data.get("soft_depends_on", []):
            if dep.startswith("gate:"):
                gate = dep.split(":", 1)[1]
                if gate not in known_gates:
                    errors.append(f"target '{name}' soft_depends_on unknown gate '{gate}'")
            elif dep not in targets:
                errors.append(f"target '{name}' soft_depends_on unknown target '{dep}'")

    for component, meta in components.items():
        primary_profile = meta.get("primary_profile")
        if not primary_profile:
            errors.append(f"component '{component}' missing primary_profile")
        elif primary_profile not in KNOWN_PROFILES:
            errors.append(f"component '{component}' has unknown primary_profile '{primary_profile}'")

        component_targets = [name for name, data in targets.items() if data.get("component") == component]
        if not component_targets:
            errors.append(f"component '{component}' has no targets")

    for name, data in targets.items():
        component = data.get("component")
        if component and component in components:
            continue
        if component and components:
            errors.append(f"target '{name}' references undeclared component '{component}'")

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


def component_profile(manifest, component):
    meta = manifest["components"].get(component, {})
    return meta.get("primary_profile") or "configured"


def component_order(manifest, topo_ordered=None):
    """Return components in an order consistent with target dependencies.

    Builds a component-level dependency graph by inspecting which component
    owns each target's depends_on entries, then runs Kahn's topo sort on
    components.  Ties are broken alphabetically for determinism.
    """
    targets = manifest["targets"]
    components = list(manifest["components"].keys())

    # Build component → set-of-component-deps from target depends_on edges
    comp_deps = {c: set() for c in components}
    comp_graph = defaultdict(list)
    comp_indegree = {c: 0 for c in components}

    for tname, tdata in targets.items():
        comp = tdata.get("component")
        if not comp or comp not in comp_deps:
            continue
        for dep_target in tdata.get("depends_on", []):
            dep_comp = targets.get(dep_target, {}).get("component")
            if dep_comp and dep_comp != comp and dep_comp not in comp_deps[comp]:
                comp_deps[comp].add(dep_comp)
                comp_graph[dep_comp].append(comp)
                comp_indegree[comp] += 1

    queue = sorted(c for c, deg in comp_indegree.items() if deg == 0)
    ordered = []
    while queue:
        node = queue.pop(0)
        ordered.append(node)
        children = sorted(comp_graph[node])
        for child in children:
            comp_indegree[child] -= 1
            if comp_indegree[child] == 0:
                queue.append(child)
                queue.sort()
    for c in components:
        if c not in ordered:
            ordered.append(c)
    return ordered


def main():
    args = sys.argv[1:]
    deps_mode = False
    soft_deps_mode = False
    component_profile_mode = False
    components_mode = False
    dispatch_mode = False
    target_name = None
    if len(args) >= 2 and args[0] == "--deps":
        deps_mode = True
        target_name = args[1]
        args = args[2:]
    elif len(args) >= 2 and args[0] == "--soft-deps":
        soft_deps_mode = True
        target_name = args[1]
        args = args[2:]
    elif len(args) >= 2 and args[0] == "--component-profile":
        component_profile_mode = True
        target_name = args[1]
        args = args[2:]
    elif len(args) >= 2 and args[0] == "--dispatch":
        dispatch_mode = True
        target_name = args[1]
        args = args[2:]
    elif len(args) >= 1 and args[0] == "--components":
        components_mode = True
        args = args[1:]

    path = Path(args[0]) if args else Path("targets")
    try:
        manifest = parse_manifest(path)
        known_gates = parse_gate_names(Path("policy/gates.yaml"))
        errors, ordered = validate(manifest, known_gates)
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    if errors:
        for error in errors:
            print(f"ERROR: {error}", file=sys.stderr)
        return 1

    if deps_mode:
        for dep in manifest["targets"].get(target_name, {}).get("depends_on", []):
            print(dep)
        return 0

    if soft_deps_mode:
        for dep in manifest["targets"].get(target_name, {}).get("soft_depends_on", []):
            print(dep)
        return 0

    if component_profile_mode:
        print(component_profile(manifest, target_name))
        return 0

    if dispatch_mode:
        meta = manifest["components"].get(target_name, {})
        print(meta.get("libs", ""))
        print(meta.get("runner", ""))
        print(meta.get("on_fail", ""))
        return 0

    if components_mode:
        for component in component_order(manifest, ordered):
            print(component)
        return 0

    print(f"OK: {len(manifest['targets'])} orchestration targets validated")
    print("Topological order:")
    for name in ordered:
        print(f"  - {name}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
