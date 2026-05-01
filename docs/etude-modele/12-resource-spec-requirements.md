# 12 - Resource Specification Requirements

Some current resources are valid for the current runner but underspecified for
model v3. In the goal model, the requirements below are required semantics.

The migration can start in warning mode, but the goal model treats these as
normal schema expectations.

## Summary

| Requirement | Why it makes the model stronger |
|---|---|
| Condition intersection checks | Finds dependency edges that can never apply |
| Explicit capability IDs | Lets dependencies resolve by function, not by resource name |
| Provider selection | Keeps implementation providers out of dependent resources |
| Derived endpoint capabilities | Connects runtime endpoints to verification |
| Package output contracts | Separates package install names from produced binaries/apps/models/extensions |
| Custom operation contracts | Makes hidden custom behavior validatable |
| Applicability inheritance | Prevents dependents from running where providers cannot apply |
| Package desired state cleanup | Keeps `desired_value` reserved for parametric config |

## 1. Condition Intersection Checks

Every conditional dependency must satisfy this rule:

```text
resource applicability
AND relation condition
AND provider resource applicability
must not be empty.
```

Current examples that violate the goal model:

| Resource | Edge | Problem |
|---|---|---|
| `ariaflow-server` | `avahi?linux,wsl2` | resource is `requires: macos`, provider is Linux/WSL2 |
| `homebrew` | `build-deps?!brew` | resource is `requires: macos`, provider is Linux/WSL2 |

Goal-model rule:

```yaml
validation:
  condition_intersection:
    severity: error
    inputs:
      - resource.requires
      - relation.condition
      - provider.requires
```

The likely fixes are different:

| Case | Goal-model fix |
|---|---|
| `ariaflow-server -> avahi?linux,wsl2` | Replace direct provider edge with `service-discovery:mdns-publish` provider selection |
| `homebrew -> build-deps?!brew` | Decide whether Homebrew is truly macOS-only or whether Linuxbrew is supported as a separate resource |

## 2. Capability Resources Must Provide Capabilities

Capability resources must say both how to probe and what capability they provide.

| Resource | Required capability |
|---|---|
| `network-available` | `capability:network-connectivity/internet` |
| `mdns-available` | `capability:service-discovery/mdns-publish` |
| `networkquality-available` | `capability:network-probe/networkquality` |
| `docker-available` | `capability:daemon/docker` and/or `capability:socket/docker` |
| `python-venv-available` | `capability:python-feature/venv` |
| `mps-available` | `capability:hardware-accel/mps` |
| `cuda-available` | `capability:hardware-accel/cuda` |
| `systemd-available` | `capability:init-system/systemd` |
| `cgroup2-available` | `capability:kernel-feature/cgroup2` |
| `user-linger-enabled` | `capability:user-service/linger` |
| `sudo-available` | `capability:admin-authority/sudo` |

Resource shape:

```yaml
docker-available:
  element_type: managed-resource
  lifecycle:
    resource_type: capability
    convergence_profile_derived: capability
  driver:
    driver_type: capability
    probe: docker_daemon_is_running
  relations:
    - relation_type: provides
      to: capability:daemon/docker
      provides:
        satisfaction_rule: probe-passes
```

## 3. Provider Selection

Dependents consume abstract capabilities. Provider choice is a separate model
concept.

Example:

```yaml
ariaflow-server:
  relations:
    - relation_type: consumes
      to: capability:service-discovery/mdns-publish
      consumes:
        consume_strength: hard
        relation_effect: block
```

Provider selection:

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

The goal model forbids direct provider leakage like:

```yaml
depends_on:
  - avahi?linux,wsl2
```

when the real need is mDNS publishing.

## 4. Runtime Endpoints Provide HTTP Capabilities

Runtime resources with `endpoints` derive `http-endpoint` capabilities.

| Resource | Derived capability |
|---|---|
| `ollama` | `capability:http-endpoint/ollama.tags` |
| `open-webui-runtime` | `capability:http-endpoint/open-webui.root` |
| `flowise-runtime` | `capability:http-endpoint/flowise.root` |
| `openhands-runtime` | `capability:http-endpoint/openhands.root` |
| `n8n-runtime` | `capability:http-endpoint/n8n.root` |
| `qdrant-runtime` | `capability:http-endpoint/qdrant.collections` |
| `unsloth-studio` | `capability:http-endpoint/unsloth-studio.root` |
| `unsloth-studio-service` | `capability:http-endpoint/unsloth-studio.root` |
| `ariaflow-server` | `capability:http-endpoint/ariaflow.api`, `capability:http-endpoint/aria2.rpc` |
| `ariaflow-dashboard` | `capability:http-endpoint/ariaflow.dashboard` |

Derivation rule:

```text
runtime resource endpoints[] -> provides capability:http-endpoint/<resource>.<endpoint>
```

Verification tests verify these capabilities instead of carrying their own
disconnected URL meaning.

## 5. Package Output Contracts

Package resources must declare or derive what they make available.

| Package class | Output capability |
|---|---|
| CLI tools | `binary/<bin>` |
| Homebrew casks | `app-bundle/<app>` and sometimes `binary/<helper>` |
| npm globals | `node-package/<package>` and `binary/<bin>` |
| pip groups | `python-package-set/<group>` and optional `python-import/<module>` |
| VS Code extensions | `app-extension/vscode/<id>` |
| Ollama models | `ai-model/ollama/<model>` |
| Python runtime | `language-runtime/python` and `binary/python3` |
| Avahi | `binary/avahi-publish-service` |

Example:

```yaml
ollama-model-llama3.2:
  relations:
    - relation_type: consumes
      to: capability:daemon/ollama
      consumes:
        consume_strength: hard
        relation_effect: block
    - relation_type: provides
      to: capability:ai-model/ollama/llama3.2
```

## 6. Custom Operation Contracts

`driver.driver_type: custom` cannot stay opaque in model v3.

Current custom resources include:

```text
ai-apps-template
unsloth-studio
unsloth-studio-service
docker-desktop
docker-daemon
docker-resources
docker-privileged-ports
xcode-command-line-tools
homebrew
system-composition
```

Each must choose one path:

| Path | Use when |
|---|---|
| Promote to named driver | Behavior is reusable or important enough to validate |
| Add `operation-contract` | Behavior stays resource-specific but phases are explicit |

Example:

```yaml
operation_contract:
  resource: docker-resources
  operation_phases:
    observe:
      command: docker_resources_observe
      output: config-value
    apply:
      command: docker_resources_apply
      requires:
        - capability:daemon/docker
    verify:
      command: docker_resources_observe
      expected: desired_cmd
```

## 7. Applicability Inheritance

When a hard dependency is only available on some hosts, the dependent resource
inherits that practical applicability unless another provider can satisfy the
same capability.

Example:

```text
ollama-model-* depends on ollama
ollama requires launchd or systemd
therefore ollama-model-* effectively requires launchd or systemd too
```

In the goal model, this derived applicability is visible:

```yaml
derived_applicability:
  from_hard_dependencies:
    - ollama.requires
```

Goal-model validation:

```text
resource has no declared applicability, but all providers for a hard consume are
restricted. Derived applicability must be declared or accepted explicitly.
```

## 8. Package Desired State Cleanup

`desired_value` means parametric config value. Package resources use package
desired state instead.

Current example:

```yaml
avahi:
  resource_type: package
  convergence_profile_derived: configured
  desired_value: '@present'
```

Goal-model shape:

```yaml
avahi:
  lifecycle:
    resource_type: package
    convergence_profile_derived: configured
    state_model_derived: package
  desired_state:
    installation: Configured
    health: Healthy
```

If a package only needs to be present, that is represented by the
package state model, not by a parametric value field.

## Goal-Model Validation

These are required validation checks for the goal model:

1. `condition_intersection`: impossible conditional edges.
2. `capability_resource_output`: capability resource without `provides`.
3. `runtime_endpoint_output`: endpoint without derived `http-endpoint`.
4. `package_output_contract`: package resource without typed output.
5. `custom_operation_contract`: custom resource without explicit contract.
6. `derived_applicability`: resource applicability narrowed by hard providers.
7. `package_desired_value`: package resource uses `desired_value`.
8. `provider_leak`: dependent names provider resource where an abstract
   capability exists.

## Power Gained

These requirements make the model stronger in practical ways:

| Requirement | Power gained |
|---|---|
| Condition intersection | Detects dead edges and unreachable resource paths |
| Capability IDs | Enables provider-independent dependency resolution |
| Provider selection | Allows clean macOS/Linux/WSL alternatives |
| Endpoint derivation | Makes verification traceable to runtime promises |
| Package output contracts | Lets the validator know what installs actually produce |
| Custom operation contracts | Makes custom shell behavior auditable |
| Applicability inheritance | Prevents hidden platform/runtime assumptions |
| Desired state cleanup | Keeps package/config semantics orthogonal |
