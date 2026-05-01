# 04 - Types, Profiles, And State Model

The complete model must separate four notions that were previously mixed:

```text
element_type  : managed-resource | preflight-gate | verification-test
type          : manifest nature of the resource
profile       : convergence profile
state_model_derived   : observed/desired comparison model
```

## Live Convergence Types

| YAML `resource_type` | Role | Count |
|---|---|---:|
| `package` | Install or update a software artifact | 95 |
| `config` | Converge a file, link, preference, or value | 27 |
| `runtime` | Bring a service/process into the desired execution state | 13 |
| `capability` | Observe a currently available capability | 11 |
| `precondition` | Local prerequisite for a config/runtime resource | 1 |

`gate` is not a live convergence `type`. It is a preflight class.

## Live Convergence Profiles

| YAML `convergence_profile_derived` | Role | Count |
|---|---|---:|
| `configured` | Stable presence/configuration | 105 |
| `parametric` | Current value compared with a desired value | 18 |
| `runtime` | Expected runtime is running | 13 |
| `capability` | Observe-only probe | 11 |

## State Axes

Each resource is interpreted through state axes:

| Axis | Question |
|---|---|
| `installation` | absent, installed, configured? |
| `runtime` | never started, stopped, running? |
| `health` | healthy, degraded, unavailable, outdated? |
| `admin` | is the action authorized? |
| `dependencies` | are dependencies ready? |
| `config_value` | observed value for parametric resources |

Example:

```yaml
desired_state:
  installation: Configured
  runtime: Running
  health: Healthy
  admin: Enabled
  dependencies: DepsReady
```

## Type / Profile / State Model Relation

| Case | `type` | `profile` | `state_model_derived` |
|---|---|---|---|
| Installed CLI | `package` | `configured` | implicit `package` |
| OS preference | `config` | `parametric` | `parametric` |
| Docker daemon | `runtime` | `runtime` | runtime state-model |
| MPS available | `capability` | `capability` | observe-only |
| Compose file | `config` | `configured` | `config` |

## Refactoring Point

The validator makes implicit derivations explicit:

```text
resource_type=package + convergence_profile_derived=configured => state_model_derived=package
resource_type=config  + convergence_profile_derived=parametric => state_model_derived=parametric
resource_type=runtime + convergence_profile_derived=runtime    => state_model_derived=runtime
```

This will make the docs, validator, and execution layer more coherent.
