# Performance Analysis

## Root Cause Summary

The script is slow because of **~300+ independent Python subprocess invocations per run**, each independently parsing YAML files from disk, combined with **~700-1000 subshell forks**. There is no inter-invocation caching for YAML or manifest data.

Estimated dry-run time (no installs, 60 targets): **90-110 seconds**

---

## Bottleneck #1 — YAML Parsed Fresh on Every Call (highest impact)

Each call to `python3 tools/read_config.py` or `python3 tools/validate_targets_manifest.py` starts a new Python process, loads the YAML file from disk, parses it, returns one value, and exits. The parsed data is thrown away.

**Per target, minimum calls:**

| Call | File:Line | Purpose |
|---|---|---|
| `read_config.py --target-get-many` | `ucc_targets.sh:193` | Target config (observe) |
| `read_config.py --evidence` | `ucc_targets.sh:21` | Evidence collection |
| `read_config.py --target-get` (×3) | `ucc_targets.sh:266-269` | Profile, install cmd, update cmd |
| `validate_targets_manifest.py --deps` | `ucc_targets.sh:107` | Dependency evidence |
| `validate_targets_manifest.py --soft-deps` | `ucc_targets.sh:122` | Soft-dep evidence |

**Total per target: 6-8 python3 calls**
**Total per run (60 targets): ~400 python3 invocations**

Python startup alone costs ~50-100ms per invocation → **20-40s lost to startup overhead alone**.

---

## Bottleneck #2 — Component Dispatch Re-parses Manifest per Component

`install.sh:466` calls `validate_targets_manifest.py --dispatch $comp` once per component (13 components). Each call re-parses the entire `ucc/` directory.

**13 manifest parses before any target runs.**

---

## Bottleneck #3 — Observe Function Called up to 3× per Target

`_ucc_execute_target` in `ucc_targets.sh` calls `$observe_fn` at:
- Line 903: initial state check
- Line 953: post-update verify (if update taken)
- Line 1032: post-install verify (if install taken)

Each observation triggers 2-3 subprocess calls. For 60 targets: **~180 observe invocations**.

---

## Bottleneck #4 — JSON State Validation via Python

`lib/ucc_asm.sh` uses inline `python3 -c` heredocs for every state comparison:

| Function | File:Line | Called when |
|---|---|---|
| `_ucc_is_json_obj` | `ucc_asm.sh:18` | Every state check (×2 per target) |
| `_ucc_json_equal` | `ucc_asm.sh:55` | Every equality check (×1 per target) |
| `_ucc_display_state` | `ucc_asm.sh:73` | Every state display (×1-2 per target) |

~4 Python invocations per target × 60 targets = **~240 additional Python calls**.

These only check JSON structure or extract fields — overkill for simple string operations.

---

## Bottleneck #5 — Display Name Cache Uses Linear Search

`_ucc_display_name()` in `ucc_targets.sh:124-143` caches display names in two indexed bash arrays and does O(N) linear search on every lookup. Falls back to `validate_targets_manifest.py --display-name` on cache miss.

---

## What is Well-Cached (no issue)

| Cache | Covers |
|---|---|
| `_BREW_VERSIONS_CACHE` | All brew formulae/casks |
| `_PIP_VERSIONS_CACHE` | All pip packages |
| `_NPM_GLOBAL_VERSIONS_CACHE` | All npm global packages |
| `_VSCODE_EXTENSIONS_CACHE` | All VS Code extensions |
| `_OLLAMA_MODELS_CACHE` | All Ollama models |
| `_UCC_ENDPOINT_CACHE_*` | Endpoint metadata |

These are all populated once and reused correctly — no problem here.

---

## Subprocess Count Estimate (full run, no actual installs)

| Category | Count |
|---|---|
| Python subprocess invocations (YAML/manifest/JSON) | ~300-400 |
| Subshell forks `$(...)` | ~700-1000 |
| Brew subprocess calls | 5-10 |
| Other tools (npm, pip, code, ollama) | 10-30 |
| **Total** | **~1000-1500** |

---

## Optimization Opportunities (prioritized)

### 1. Batch YAML reads per target (high impact, medium effort)

Instead of 6 separate `python3 read_config.py` calls per target, one call returning all needed fields would reduce Python startup overhead by ~80%.

### 2. Batch all `--dispatch` queries in one call (high impact, low effort)

Replace the per-component `validate_targets_manifest.py --dispatch $comp` loop with a single call returning all components. Saves 13 Python invocations before targets even start.

### 3. Replace Python JSON checks with bash string patterns (medium impact, low effort)

```bash
# Instead of: _ucc_is_json_obj "$observed"  (spawns python3)
# Use:        [[ "$observed" == "{"* ]]
```

Eliminates ~240 Python invocations per run.

### 4. Use associative array for display name cache (low impact, trivial effort)

```bash
# Instead of two indexed arrays with O(N) search:
declare -A _UCC_DISPLAY_NAME_CACHE
_UCC_DISPLAY_NAME_CACHE["$target"]="$display_name"  # O(1) lookup
```

### 5. Cache manifest dependency lookups (medium impact, medium effort)

Load all `--deps` and `--soft-deps` once at component start and store in memory rather than querying per target.

---

## Decision

No changes made. Analysis documented for future reference.

The optimizations above would reduce dry-run time from ~100s to an estimated ~20-30s. The highest-leverage change is batching YAML reads per target (Priority 1), which alone could cut total Python invocations by 60-70%.
