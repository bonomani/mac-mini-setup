# 02 - Components / Scopes

The study's "scope" concept corresponds to the live `component` field.
The recommended refactoring term is therefore:

```text
component = logical grouping + display grouping
```

In the goal model, `software` and `system` are also elements, but at a
higher level:

```text
layer element: software
  contains component: cli-tools
    contains resource: cli-jq

layer element: system
  contains component: system
    contains resource: sudo-available
```

Containment is also a relation:

```text
relation(relation_type=contains, contains.cardinality=one-to-many)
```

## Live Convergence Components

| Universe | Component | Role | Resources |
|---|---|---|---:|
| software | `ai-apps` | Ollama, models, compose stack, AI services | 16 |
| software | `ai-python-stack` | Python, pyenv, pip groups, acceleration, Unsloth | 25 |
| software | `build-tools` | Optional Rust/RDP/build side tools | 3 |
| software | `cli-tools` | CLI tools, third-party GUI apps, shell config | 54 |
| software | `docker` | Docker Desktop/daemon/resources/capability | 5 |
| software | `network-services` | mDNS, NetworkQuality, ariaflow | 5 |
| software | `node-stack` | nvm, Node LTS, npm globals | 6 |
| software | `software-bootstrap` | Network, build deps, Xcode CLT, Homebrew | 5 |
| software | `vscode-stack` | VS Code, CLI, settings, extensions | 10 |
| system | `linux-system` | systemd, cgroup v2, linger | 3 |
| system | `system` | macOS pmset/defaults/softwareupdate composition | 15 |

Live convergence totals:

```text
software resources     : 129
system resources       : 18
total convergence    : 147
verification tests   : 23  (outside the managed-resource graph)
```

## Conceptual Universes

```text
software convergence
  -> packages, runtimes, CLIs, apps, services

system convergence
  -> OS settings, system capabilities, admin/runtime prerequisites

verification
  -> verification tests, outside convergence
```

## Criteria For Creating A Component

Create a new component only if at least three conditions are true:

- multiple resources share a stable functional domain;
- they have a coherent convergence order;
- the user benefits from a separate display header;
- they share Bash libraries or a runner;
- they share policies or platforms.

Otherwise, enrich an existing component.

## Refactoring Point

The goal model uses one vocabulary:

```text
component     = YAML field and source of truth
display_scope = compatibility/display projection if UI grouping diverges later
```
