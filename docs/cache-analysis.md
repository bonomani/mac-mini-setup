# Cache System Analysis

## Overview

The caching system uses global string variables (exported for subshell access) to avoid repeated subprocess calls during a run. Each cache is populated once at startup or before its component runner, then refreshed after mutations.

## Cache Inventory

| Cache | Type | Populated by | Invalidated after update |
|---|---|---|---|
| `_PIP_VERSIONS_CACHE` | JSON string | `pip_cache_versions()` | YES — full repopulate |
| `_VSCODE_EXTENSIONS_CACHE` | tab-delimited string | `vscode_extensions_cache_versions()` | YES — full repopulate |
| `_BREW_VERSIONS_CACHE` | multiline string | `brew_cache_versions()` | YES — full repopulate |
| `_BREW_OUTDATED_CACHE` | multiline string | `brew_cache_outdated()` | YES — via `brew_refresh_caches()` in `always-upgrade` mode only |
| `_OLLAMA_MODELS_CACHE` | multiline string | `ollama_model_cache_list()` | YES — full repopulate |
| `_NPM_GLOBAL_VERSIONS_CACHE` | tab-delimited string | `npm_global_cache_versions()` | YES — full repopulate |
| `_UCC_ENDPOINT_CACHE_*` | indexed arrays | `_ucc_endpoint_fields()` | N/A — read-only config |
| `_UCC_DISPLAY_NAME_CACHE_*` | indexed arrays | `_ucc_display_name()` | N/A — read-only metadata |
| `_AI_*_CACHE` (Docker images) | tab-delimited string | `_ai_warm_metadata_cache()` | YES — full reset, local scope |

## Brew Outdated Cache — Design Note

`_BREW_OUTDATED_CACHE` is only consulted when `UIC_PREF_PACKAGE_UPDATE_POLICY == always-upgrade` (see `ucc_brew.sh:63,73`). In that mode, `brew_refresh_caches()` calls `brew_cache_outdated()`, which refreshes both version and outdated caches. In `install-only` mode, the outdated cache is never read and only `brew_cache_versions()` is called. No stale data risk.

## Invalidation Scope — Global vs Incremental

All package-manager caches use **full repopulate** (blow away entire cache and re-query) rather than incremental updates (update only the changed entry).

### Why incremental updates are unsafe for pip and brew

When installing or upgrading a package, the package manager may silently upgrade transitive dependencies:

```
pip install langchain
  → upgrades pydantic 1.10 → 2.0   (transitive)
  → upgrades typing-extensions 4.5 → 4.8  (transitive)

brew install git
  → upgrades openssl, pcre2  (transitive)
```

An incremental cache update would only reflect the top-level package change. Transitive dependency versions would remain stale in the cache for the rest of the run.

### Where incremental updates would be safe

| Cache | Safe for incremental? | Reason |
|---|---|---|
| `_OLLAMA_MODELS_CACHE` | YES | Models are independent; no transitive deps |
| `_VSCODE_EXTENSIONS_CACHE` | YES | Extensions are isolated; no transitive deps tracked by this cache |
| `_NPM_GLOBAL_VERSIONS_CACHE` | YES | Only top-level globals are tracked |
| `_PIP_VERSIONS_CACHE` | NO | Transitive dependencies modified silently |
| `_BREW_VERSIONS_CACHE` | NO | Transitive dependencies modified silently |

### Decision: keep full repopulate

The performance cost of full repopulate is only paid when a package is actually installed or upgraded (idempotent runs do not trigger invalidation). The real bottleneck in a setup run is network I/O (downloads), not cache subprocess calls. Incremental updates for Ollama/VSCode/npm would yield negligible gains while adding fragile string-manipulation logic.

**Current approach is correct and sufficient.**
