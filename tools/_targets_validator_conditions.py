"""Condition parsing for `validate_targets_manifest.py`.

Extracted 2026-04-28 (PLAN refactor #3, slice 1). The main validator
re-imports these symbols so existing test imports
(`from validate_targets_manifest import _resolve_conditional_dep`)
keep working unchanged.
"""
import os
import re

def _host_match_values():
    """Return the set of values that a conditional dep can match against."""
    vals = set()
    for var in ["HOST_PLATFORM", "HOST_PLATFORM_VARIANT", "HOST_ARCH",
                "HOST_OS_ID", "HOST_PACKAGE_MANAGER"]:
        v = (os.environ.get(var) or "").strip()
        if v:
            vals.add(v)
    # Also add fingerprint segments
    fp = (os.environ.get("HOST_FINGERPRINT") or "").strip()
    for seg in fp.split("/"):
        if seg:
            vals.add(seg)
    return vals


def _host_named_values():
    """Return dict mapping short names to values for version comparisons.
    e.g. {'macos': '15.4', 'ubuntu': '22.04', 'wsl2': None}
    """
    vals = {}
    # Platform → OS version
    os_id = (os.environ.get("HOST_OS_ID") or "").strip()
    if os_id:
        # "macos-15.4" → macos=15.4, "ubuntu-22.04" → ubuntu=22.04
        parts = os_id.split("-", 1)
        if len(parts) == 2:
            vals[parts[0]] = parts[1]
    # Also map platform names
    for var in ["HOST_PLATFORM", "HOST_PLATFORM_VARIANT"]:
        v = (os.environ.get(var) or "").strip()
        if v and v not in vals:
            vals[v] = os_id.split("-", 1)[1] if "-" in os_id else ""
    return vals


def _version_compare(actual, op, required):
    """Compare version strings: '15.4' >= '14' → True."""
    try:
        from packaging.version import Version
        return {
            ">=": lambda a, b: Version(a) >= Version(b),
            "<=": lambda a, b: Version(a) <= Version(b),
            ">":  lambda a, b: Version(a) > Version(b),
            "<":  lambda a, b: Version(a) < Version(b),
            "==": lambda a, b: Version(a) == Version(b),
            "!=": lambda a, b: Version(a) != Version(b),
        }[op](actual, required)
    except Exception:
        # Fallback: simple numeric comparison
        try:
            a = tuple(int(x) for x in actual.split("."))
            b = tuple(int(x) for x in required.split("."))
            return {
                ">=": lambda: a >= b, "<=": lambda: a <= b,
                ">": lambda: a > b, "<": lambda: a < b,
                "==": lambda: a == b, "!=": lambda: a != b,
            }[op]()
        except Exception:
            return False


_CONDITION_VERSION_RE = re.compile(r'^(!?)(\w+)(>=|<=|>|<|==|!=)(.+)$')


def _eval_single_condition(cond, host_values):
    """Evaluate a single condition atom against host values.
    Returns True/False.
    """
    # Version comparison: name>=version
    m = _CONDITION_VERSION_RE.match(cond)
    if m:
        negate, name, op, version = m.groups()
        named = _host_named_values()
        actual = named.get(name, "")
        result = _version_compare(actual, op, version) if actual else False
        return not result if negate else result

    # Negation: !value
    if cond.startswith("!"):
        return cond[1:] not in host_values

    # Simple match: value
    return cond in host_values


def _resolve_conditional_dep(entry, host_values=None):
    """Parse 'target?condition' → (target_name, included).
    Conditions (comma = OR):
      ?value                     → match host value
      ?!value                    → NOT match
      ?name>=version             → version compare
      ?macos>=14,linux,wsl2      → OR: any condition true → included
    For union mode (host_values=None), returns (target_name, True) always.
    """
    if "?" not in entry:
        return entry, True
    target, condition = entry.split("?", 1)
    if host_values is None:
        return target, True

    # Split on comma for OR logic
    for cond in condition.split(","):
        cond = cond.strip()
        if cond and _eval_single_condition(cond, host_values):
            return target, True
    return target, False
