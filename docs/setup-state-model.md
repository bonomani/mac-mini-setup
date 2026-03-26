# ASM Setup State Model: mac-mini-setup

This document defines the ASM-aligned state model used for the
`mac-mini-setup` scope.

The model is generic at the host level and concrete at the component
level. Each setup component is treated as a software target with a
bounded lifecycle and explicit admissible transitions.

## 1. Modeling boundary

Scope:
- AI workstation setup
- macOS is the full-profile target; Linux and WSL use the portable subset
- 13 governed components across two layers:

  Software layer (`ucc/software/`) — presence convergence:
  - `homebrew`
  - `git`
  - `docker`
  - `python`
  - `ollama`
  - `ai-python-stack`
  - `ai-apps`
  - `dev-tools`

  System layer (`ucc/system/`) — value convergence:
  - `git-config`
  - `docker-config`
  - `macos-defaults`
  - `system`

  Verification (`tic/software/`, `tic/system/`):
  - `verify`

Modeling rule:
- the host setup state is a composition of component states
- software-layer components use the `presence` or `configured` ASM profile
- `ai-apps` uses both a parametric configuration target (`ai-stack-compose-file`)
  and a runtime target (`ai-stack-running`) because the desired stack
  definition and the running stack are governed separately
- system-layer value-convergence components (`docker-config`, `macos-defaults`) use the
  `parametric` ASM profile (axes include `config_value`)
- the `system` component uses a parametric composition target
  (`system-composition`) that derives whole-machine state from the
  status of required governed subsystem targets in the current run
- system-layer presence-only components (`git-config`) use the `configured` ASM profile
- each mutable component uses the ASM software-profile style axes:
  - `installation_state`
  - `runtime_state`
  - `health_state`
  - `admin_state`
  - `dependency_state`
- `verify` is verification-only and does not converge state itself

## 2. Component state axes

### Installation / presence

Used values in this project:
- `Absent`
- `Installing`
- `Installed`
- `Configuring`
- `Configured`
- `Upgrading`
- `InstallFailed`
- `ConfigFailed`
- `UpgradeFailed`

Meaning:
- `Installed` means the package, app, or on-disk artifact exists
- `Configured` means the component is ready for its intended role in the
  workstation setup
- `Upgrading` is used for update mode when an existing component is
  intentionally reconciled again

### Runtime / execution

Used values in this project:
- `NeverStarted`
- `Starting`
- `Running`
- `Stopped`
- `Crashed`

Meaning:
- runtime is relevant only for service-bearing components such as
  Docker-managed apps, launchd services, or the Ollama API
- non-service components may remain `NeverStarted` or `Stopped` while
  still being validly `Configured`

### Health / availability

Used values in this project:
- `Unknown`
- `Healthy`
- `Degraded`
- `Unhealthy`
- `Unavailable`

Meaning:
- health is resolved from verification probes and readiness checks
- `Unavailable` means the expected endpoint, CLI, or service is not
  currently reachable

### Administration / intention

Used values in this project:
- `Enabled`
- `Maintenance`
- `Disabled`

Meaning:
- `Maintenance` is used when a component is intentionally stopped or
  gated while the rest of the setup may proceed

### Dependencies / technical readiness

Used values in this project:
- `DepsUnknown`
- `DepsReady`
- `DepsDegraded`
- `DepsFailed`

Meaning:
- dependency readiness is used for preflight gates and admissible
  target-state checks
- examples:
  - Docker daemon reachable
  - Docker settings file present
  - Ollama API reachable
  - sudo available for macOS defaults

### Configuration value (optional — parametric targets only)

Used by: `docker-config`, `macos-defaults`, `ai-apps` stack definition target,
`system` composition target

Meaning:
- carries the actual observed or desired configuration value as a string
- enables value-level convergence: the engine re-applies when the value
  drifts from the desired even though `installation_state=Configured`
- absent on presence-only targets; present only when the `parametric`
  profile is selected
- examples: `mem=48GB cpu=10`, `0` (pmset sleep value), `1` (dock autohide)
- stack-definition example:
  `marker=# ai-stack v2 services=flowise,n8n,open-webui,openhands,qdrant`
- system-composition example:
  `kind=host-composition targets=ai-stack-running,ariaflow-web-service,docker-resources,docker-running,finder-show-hidden=1,git,git-global-config,homebrew,ollama-service,pmset-ac-sleep=0,python,unsloth-studio-launchd`

## 3. Derived states

Derived states are computed, not primary.

Minimum derived states used here:
- `Present`
- `Ready`
- `Operational`
- `Broken`

Additional derived states used here:
- `ManagedStop`
- `Transient`
- `NonOperational`

Project interpretation:
- `Ready` means a component is admissible for the next convergence step
- `Operational` means the component is configured and, when applicable,
  running or externally reachable
- `Broken` means install/config/update or runtime health is in failure
- `Transient` covers install, configure, and upgrade windows

## 4. Admissible target-state rules

UIC preflight and UCC convergence both depend on this state model.

Examples:
- Docker settings should not be targeted as `Configured` until the
  Docker settings file is present
- Ollama service should not be targeted as `Running` until the API gate
  is satisfied or intentionally bypassed as a soft warning
- AI apps stack definition should not be targeted as `Configured` until
  the Compose template exists and the deployed stack file matches the
  expected marker and service set
- AI apps runtime should not be targeted as `Running` until Docker
  daemon and Docker Compose CLI readiness are satisfied or intentionally
  tolerated as soft warnings
- macOS defaults may remain outside the target path when `sudo` is not
  available because that gate is soft and component-scoped

## 5. Transition interpretation

Component transitions are interpreted through the following lifecycle:
- `Absent -> Installing -> Installed -> Configuring -> Configured`
- `Configured -> Upgrading -> Configured`
- failure transitions may end in:
  - `InstallFailed`
  - `ConfigFailed`
  - `UpgradeFailed`

Runtime-bearing components may additionally use:
- `NeverStarted -> Starting -> Running`
- `Running -> Stopped`
- `Running -> Crashed`

For the AI apps stack the effective interpretation is split:
- definition convergence:
  `Absent -> Configuring -> Configured`
- runtime convergence:
  `Stopped -> Starting -> Running`
- readiness evidence is strengthened by TIC HTTP endpoint probes over the
  composed services after convergence

## 6. Host-level composition

The workstation state is a composition of component states.

Host-level interpretation:
- the setup is `Ready` when mandatory component dependencies are
  admissible for the requested run mode
- the setup is `Operational` when the configured core services and tools
  required by the selected workload are available
- the setup is `Broken` when a mandatory component is in a failed state
  or a mandatory dependency is `DepsFailed`
- the `system` target is the explicit project-local bridge between
  component state and whole-machine state; it does not add new runtime
  controls by itself, but it makes the composed system state declarable
  and observable inside the existing UCC flow
- `tic/system/verify.yaml` is the explicit verification layer for
  `system-composition`; verification stays separate from convergence,
  but the relation is now declared in the project artifacts and traces
- soft-gated optional targets can remain outside the required
  `system-composition` dependency set so they do not incorrectly degrade
  whole-machine state

## 7. Evidence relationship

This model is evidenced by:
- this state-model document
- the concrete state artifact in `./setup-state-artifact.yaml`
- the executable validator in `../tools/validate_setup_state_artifact.py`
- UIC gate and preference logic in `../lib/uic.sh`
- UCC declaration/result artifacts emitted by `../lib/ucc.sh`
- TIC verification oracles in `../tic/software/verify.yaml` and `../tic/system/verify.yaml`
- the system TIC suite explicitly verifies `system-composition` and
  treats the rest of its checks as evidence for that system target
- component YAML manifests in `../ucc/software/` and `../ucc/system/`
- stack runtime composition template in `../stack/docker-compose.yml`
- AI apps convergence logic in `../lib/ai_apps.sh`
- parametric profile definition in `../policy/profiles.yaml`
