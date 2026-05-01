# 03 - Capabilities, Provides, Consumes

A capability is what an element makes available once converged.

A capability can also be the **observable form of a host fact**, exposed
through a *sonde* — a `managed-resource` of `resource_type: capability` by
convention named with the suffix `-available`. The sonde lifts a host fact
into the graph so other resources can `consumes` it explicitly. See
`01-elements.md` § Element / Fact Continuum.

The current model often implies capabilities through resource names or drivers.
For robust refactoring, they are explicit:

```yaml
provides:
  - capability_type: binary
    name: jq

consumes:
  - capability_type: package-manager
    name: brew
```

## Why Add `provides` / `consumes`

`depends_on` expresses a resource -> resource link resolved for the scheduler.

`provides` / `consumes` expresses the source functional link:

```text
resource A consumes capability X
resource B provides capability X
=> the validator can generate or verify depends_on: A -> B
```

This can detect:

- a missing dependency;
- an overly specific dependency;
- a backend that changes the real dependency;
- a verification check that does not correspond to any provider resource.

## Hard Consume / Soft Consume

The hard/soft distinction belongs to `consumes`:

```yaml
relations:
  - relation_type: consumes
    to:
      capability_type: binary
      name: python3
    consume_strength: hard
    relation_effect: block

  - relation_type: consumes
    to:
      capability_type: network-probe
      name: networkquality
    consume_strength: soft
    relation_effect: warn
```

A `hard consume` must be satisfied before convergence. A `soft consume`
improves order, evidence, or run quality, but does not necessarily block the
action.

## Capability Families

| # | Family | Definition | Examples |
|---|---|---|---|
| C1 | `binary` | Invocable command | `jq`, `rg`, `docker`, `code` |
| C2 | `package-manager` | Usable package manager | `brew`, `pip`, `npm`, `native-pm` |
| C3 | `language-runtime` | Activatable runtime or toolchain | `python`, `node`, `pyenv`, `nvm` |
| C4 | `python-import` | Importable Python module | `torch`, `transformers`, `langchain` |
| C5 | `app-extension` | Extension installed in an application | VS Code extensions |
| C6 | `daemon` | Available process/service | `ollama`, Docker daemon |
| C7 | `socket` | Available local socket | Docker socket |
| C8 | `http-endpoint` | Healthy local URL | Open WebUI, Ollama API, Qdrant |
| C9 | `compose-stack` | Active Docker Compose topology | `ai-stack-compose-running` |
| C10 | `ai-model` | Present/loadable local model | `llama3.2`, `nomic-embed-text` |
| C11 | `config-file` | Declared file present/conformant | VS Code settings, compose file |
| C12 | `os-setting` | OS setting at the desired value | `pmset`, Finder, Dock |
| C13 | `network-probe` | Available network diagnostic/probe tool | `networkquality` |
| C14 | `hardware-accel` | Usable hardware acceleration | MPS, CUDA |
| C15 | `admin-authority` | Elevation capability | `sudo-available` |
| C16 | `update-policy` | Update policy configured | softwareupdate schedule |
| C17 | `service-discovery` | Local service discovery/publishing capability | mDNS, Bonjour, Avahi |
| C18 | `python-package-set` | Resolved Python package set | requirements.txt, lockfile |
| C19 | `python-feature` | Higher-level Python capability | torch+cuda, tokenizers |
| C20 | `app-bundle` | Installed application bundle | macOS .app, Linux .desktop |
| C21 | `network-connectivity` | Reachable network destination | internet, dns, gateway |
| C22 | `kernel-feature` | Kernel-level feature toggle | systemd, launchd, btrfs |
| C23 | `init-system` | Active init/service manager | launchd, systemd |
| C24 | `user-service` | Per-user managed service | launchd LaunchAgent, systemd --user |
| C25 | `node-package` | Resolved Node package | npm/pnpm package |
| C26 | `hypervisor-runtime` | Active hypervisor | qemu, hyperv, vmware-fusion |
| C27 | `vm-runtime` | Running virtual machine | named VM instance |
| C28 | `vm-snapshot` | Existing VM snapshot | named snapshot |

The list is **open**: lib-registry's `CAPABILITY_TYPE_KNOWN` is the
authoritative live enumeration; this table tracks the named families
documented at the spec level.

## Capability Identity

Before adding capabilities to live YAML, give each capability a stable,
scoped identity. A plain `{capability_type, name}` pair is useful, but not always enough.

```yaml
capability:
  capability_type: binary
  name: jq
  capability_scope: host
  external: false
  qualifiers: {}
```

Recommended identity fields:

| Field | Role |
|---|---|
| `capability_type` | Capability family, such as `binary`, `http-endpoint`, `package-manager` |
| `name` | Stable local name inside the family |
| `capability_scope` | `host`, `user`, `component`, `container`, `service`, or `external` |
| `external` | True when the capability is outside the managed resource graph |
| `qualifiers` | Extra disambiguation such as port, app id, package manager, or runtime |

This avoids collisions such as `python` as a language runtime, `python3` as a
binary, and Python packages as import capabilities.

The provider is not part of capability identity. The provider is connected by
a `provides` relation:

```yaml
relations:
  - relation_type: provides
    from: managed-resource:cli-jq
    to: capability:binary/jq
```

## Provider Selection

Some capabilities can be satisfied by more than one provider. This is
modeled explicitly instead of leaking provider names into every dependent
resource.

```yaml
provider_selection:
  capability: capability:service-discovery/mdns-publish
  strategy: first-available
  candidates:
    - provider: external-provider:bonjour-macos
      condition:
        equals:
          fact: platform
          value: macos
    - provider: managed-resource:avahi
      condition:
        any:
          - equals:
              fact: platform
              value: linux
          - equals:
              fact: platform_variant
              value: wsl2
```

Rule:

```text
dependents consume the capability.
provider selection chooses how that capability is satisfied.
dependents do not depend directly on every provider implementation.
```

## Derived Endpoint Capabilities

Runtime resources that declare `endpoints` derive
`http-endpoint` capabilities unless they override that derivation.

```yaml
endpoints:
  - name: Qdrant
    scheme: http
    host: localhost
    port: 6333
    path: /collections

derived_provides:
  - capability:http-endpoint/qdrant.collections
```

This makes verification tests point at the same capability that the runtime
resource claims to provide.

## Complete Example

```yaml
cli-jq:
  relations:
    - relation_type: provides
      to:
        capability_type: binary
        name: jq
      consume_strength: hard
    - relation_type: consumes
      to:
        capability_type: package-manager
        any:
          - brew
          - native-pm
      consume_strength: hard
```

```yaml
vscode-ext-ms-python.python:
  relations:
    - relation_type: provides
      to:
        capability_type: app-extension
        host: vscode
        id: ms-python.python
      consume_strength: hard
    - relation_type: consumes
      to:
        capability_type: binary
        name: code
      consume_strength: hard
```

## Relation With Verification

A verification test verifies a declared capability:

```yaml
verification-test:
  verifies:
    - resource: ollama
      provides:
        capability_type: http-endpoint
        port: 11434
```

Verification therefore becomes capability proof, not a second implicit graph.

## CapabilityEdge — shared shape

The three resource-level lists `provides[]`, `consumes[]`, and the
verification-test `verifies[]` all carry edges to capabilities. They share
a common super-form:

```yaml
CapabilityEdge :=
  to:               Capability                # capability_type + name + scope + qualifiers
  condition?:       Predicate
  relation_source:  enum
  modifiers:                                  # vary by parent list
    consumes: { consume_strength, relation_effect }
    provides: { provider_scope, satisfaction_rule }
    verifies: { oracle, evidence_level }
```

The full super-form table for shared shapes (Predicate, Contract,
CapabilityEdge, GeneratedFile, Generator, Identifiable) lives in
`09-executable-contract-and-orthogonality.md` § Shared Super-Forms.
