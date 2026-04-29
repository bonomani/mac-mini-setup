"""Driver-backend metadata + dependency graph helpers for the validator.

Extracted 2026-04-29 (PLAN refactor #3, slice 3). Re-imported into the
main module so existing tests using these names keep working.
"""
from __future__ import annotations

import os

from _targets_validator_schema import DRIVER_META
from _targets_validator_conditions import (
    _host_match_values,
    _resolve_conditional_dep,
)

PKG_BACKEND_META = {
    "brew":      ("homebrew",        "brew"),
    "brew-cask": ("homebrew",        "brew-cask"),
    "native-pm": ("build-deps",      "native-package-manager"),
    "npm":       ("node-lts",        "npm"),
    "pyenv":     ("pyenv",           "pyenv"),
    "ollama":    ("ollama",          "ollama"),
    "vscode":    ("vscode-code-cmd", "vscode-marketplace"),
    "curl":      (None,              "curl"),
    "winget":    (None,              "winget"),
    "git":       (None,              "git"),
}


def _pkg_backend_names(data):
    """Return the list of backend names declared in driver.backends."""
    driver = data.get("driver") or {}
    backends = driver.get("backends") or []
    names = []
    for item in backends:
        if isinstance(item, dict) and len(item) == 1:
            for k in item.keys():
                if isinstance(k, str):
                    names.append(k)
    return names


def _driver_implicit_dep(data):
    """Return *one* implicit depends_on target for this target's driver, or None.

    For kind: pkg, returns the implicit dep of the FIRST backend that declares
    one. The full list is exposed via _driver_implicit_deps_all() below.
    """
    driver = data.get("driver") or {}
    kind = driver.get("kind", "")
    if kind == "pkg":
        for name in _pkg_backend_names(data):
            meta = PKG_BACKEND_META.get(name)
            if meta and meta[0]:
                return meta[0]
        return None
    meta = DRIVER_META.get(kind)
    return meta[0] if meta else None


def _driver_implicit_deps_all(data):
    """Union of implicit deps across all declared backends (or single driver)."""
    driver = data.get("driver") or {}
    kind = driver.get("kind", "")
    if kind == "pkg":
        deps = []
        for name in _pkg_backend_names(data):
            meta = PKG_BACKEND_META.get(name)
            if meta and meta[0] and meta[0] not in deps:
                deps.append(meta[0])
        return deps
    one = _driver_implicit_dep(data)
    return [one] if one else []


def _driver_provided_by(data):
    """Return the implicit provided_by_tool for this target's driver, or None."""
    driver = data.get("driver") or {}
    kind = driver.get("kind", "")
    if kind == "pkg":
        # First backend's tool wins; the dispatcher logs the actual one at runtime.
        for name in _pkg_backend_names(data):
            meta = PKG_BACKEND_META.get(name)
            if meta and meta[1]:
                return meta[1]
        return None
    meta = DRIVER_META.get(kind)
    return meta[1] if meta else None


def _target_dep_union(data):
    """All possible deps (union of all conditions) — for validation and ordering."""
    resolved = []
    for entry in (data.get("depends_on", []) or []):
        if isinstance(entry, str):
            target, _ = _resolve_conditional_dep(entry, host_values=None)  # union mode
            resolved.append(target)
    # Inject implicit driver dependencies (multiple, e.g. one per pkg backend).
    for implicit in _driver_implicit_deps_all(data):
        if implicit not in resolved:
            resolved.insert(0, implicit)
    # Legacy: depends_on_by_platform (backward compat until fully migrated)
    platform_deps = data.get("depends_on_by_platform") or {}
    if isinstance(platform_deps, dict):
        for items in platform_deps.values():
            if isinstance(items, list):
                resolved.extend(items)
    return resolved


def _target_soft_dep_targets(data):
    deps = []
    for dep in data.get("soft_depends_on", []) or []:
        if isinstance(dep, str) and dep and not dep.startswith("gate:"):
            deps.append(dep)
    return deps


def _target_order_union(data):
    return _target_dep_union(data) + _target_soft_dep_targets(data)


def _effective_target_deps(data):
    """Deps resolved for the current host — conditional deps evaluated."""
    host_values = _host_match_values()
    resolved = []
    for entry in (data.get("depends_on", []) or []):
        if isinstance(entry, str):
            target, included = _resolve_conditional_dep(entry, host_values)
            if included and target not in resolved:
                resolved.append(target)
    # Inject implicit driver dependency
    implicit = _driver_implicit_dep(data)
    if implicit and implicit not in resolved:
        resolved.insert(0, implicit)
    # Legacy: depends_on_by_platform (backward compat)
    platform = (os.environ.get("HOST_PLATFORM_VARIANT") or "").strip()
    family = (os.environ.get("HOST_PLATFORM") or "").strip()
    candidates = []
    if platform:
        candidates.append(platform)
    if family and family not in candidates:
        candidates.append(family)
    if family == "wsl" and "linux" not in candidates:
        candidates.append("linux")

    platform_deps = data.get("depends_on_by_platform") or {}
    if isinstance(platform_deps, dict):
        for candidate in candidates:
            items = platform_deps.get(candidate) or []
            if isinstance(items, list):
                resolved.extend(items)
    return resolved
