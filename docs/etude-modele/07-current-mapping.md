# 07 - Current Implementation Mapping → Goal Model

Per-resource mapping from the live YAML in `ucc/**/*.yaml` to the goal model
defined in `06-resource-schema.md`. Each entry shows the legacy fields, the
goal equivalent, a coverage percentage, and the validator's residual work.

**Scope: 147 managed-resources** + 23 verification tests + 1 preflight gate.

Legend

- `action_type` is one of `converge` / `observe` / `snapshot` (see 06 + 13).
  Legacy verbs (install, update, configure, start, stop, link, toggle,
  apply-stack) become branches of `operation_contract.converge.*` dispatched
  by the diff between observed and desired state.
- `tool_type` is the delegated tool. `multi` = legacy driver lists several
  backends; the goal model splits via `provider_type` × `provider_name`.
- Coverage scoring: 10 dimensions × 10% each. Missing items list the
  bridging work for that resource.
- Component-level scalar variables (parameter-space, 69 vars) are catalogued
  per component in `13-field-values-registry.md` § Component Parameter Space.

## Component: `software-bootstrap` (5 managed-resources)

#### `network-available` — Network connectivity

- Component: `software-bootstrap` · Legacy `driver.kind`: `capability`
- Goal: `resource_type=capability` · `action_type=observe` · `tool_type=none` · branch `n/a`
- Provides (sonde): `capability_type=network-connectivity, name=network`
- Probe function: `network_is_available` → `operation_contract.observe.predicate`
- `operation_contract.observe.evidence`: derived from current `evidence:` block
- Legacy `driver.probe`: `network_is_available`
- **Coverage: 90%**

#### `build-deps` — Build dependencies

- Component: `software-bootstrap` · Legacy `driver.kind`: `build-deps`
- Goal: `resource_type=package` · `action_type=converge` · `tool_type=native-pm` · branch `on_absent`
- Requires (Predicate AST): `linux,wsl2`
- **Coverage: 70%**
- Missing: requires "linux,wsl2" → AST; provided_by_tool → provider_provenance_derived

#### `xcode-command-line-tools` — Xcode Command Line Tools

- Component: `software-bootstrap` · Legacy `driver.kind`: `custom`
- Goal: `resource_type=package` · `action_type=converge` · `tool_type=varied` · branch `declared in operation_contract`
- Requires (Predicate AST): `macos`
- `operation_contract.observe.evidence`: derived from current `evidence:` block
- `observe_cmd: xcode_clt_observe` → `operation_contract.observe.state_command`
- `actions:` block → folded into `operation_contract.converge.{on_absent, on_outdated}` (legacy)
- **Coverage: 80%**
- Missing: requires "macos" → AST; provided_by_tool → provider_provenance_derived; actions.* → operation_contract.converge branches

#### `homebrew` — Homebrew

- Component: `software-bootstrap` · Legacy `driver.kind`: `custom`
- Goal: `resource_type=package` · `action_type=converge` · `tool_type=varied` · branch `declared in operation_contract`
- Consumes: `network-available`, `xcode-command-line-tools?macos`, `build-deps?!brew`
- Requires (Predicate AST): `macos`
- `operation_contract.observe.evidence`: derived from current `evidence:` block
- `observe_cmd: homebrew_observe` → `operation_contract.observe.state_command`
- `actions:` block → folded into `operation_contract.converge.{on_absent, on_outdated}` (legacy)
- **Coverage: 70%**
- Missing: conditional consumes (`?cond` syntax → condition AST); requires "macos" → AST; provided_by_tool → provider_provenance_derived; actions.* → operation_contract.converge branches

#### `brew-analytics=off` — Homebrew analytics

- Component: `software-bootstrap` · Legacy `driver.kind`: `brew-analytics`
- Goal: `resource_type=config` · `action_type=converge` · `tool_type=brew` · branch `on_drifted`
- Provides: `capability_type=os-setting` or `config-file`
- Consumes: `homebrew`
- Requires (Predicate AST): `macos`
- EXT-B: `desired_state.value: { literal: '${analytics_desired}' }`
- **Coverage: 70%**
- Missing: requires "macos" → AST; desired_value → desired_state.value (EXT-B)

## Component: `ai-apps` (16 managed-resources)

#### `ai-apps-template` — Compose template

- Component: `ai-apps` · Legacy `driver.kind`: `custom`
- Goal: `resource_type=precondition` · `action_type=converge` · `tool_type=varied` · branch `declared in operation_contract`
- `operation_contract.observe.evidence`: derived from current `evidence:` block
- **Coverage: 70%**
- Missing: state_model written explicitly → must equal state_model_derived

#### `ai-stack-compose-file` — compose file

- Component: `ai-apps` · Legacy `driver.kind`: `compose-file`
- Goal: `resource_type=config` · `action_type=converge` · `tool_type=docker` · branch `on_drifted`
- Provides: `capability_type=config-file` (compose template)
- Consumes: `ai-apps-template`, `docker-available`
- **Coverage: 70%**
- Missing: desired_state.value (config without desired)

#### `ai-stack-compose-running` — AI stack compose up

- Component: `ai-apps` · Legacy `driver.kind`: `compose-apply`
- Goal: `resource_type=runtime` · `action_type=converge` · `tool_type=docker` · branch `on_topology_diff`
- Provides: `capability_type=compose-stack` (apply-stack converge)
- Consumes: `docker-available`, `ai-stack-compose-file`
- **Coverage: 70%**

#### `open-webui-runtime` — Open WebUI

- Component: `ai-apps` · Legacy `driver.kind`: `docker-compose-service`
- Goal: `resource_type=runtime` · `action_type=observe` · `tool_type=docker` · branch `n/a (read-only)`
- Provides: `capability_type=http-endpoint × 1` (Open WebUI) — EXT-A
- Consumes: `ai-stack-compose-running`
- `endpoints[]` (1) → folded into `provides` qualifiers
- Legacy `driver.service_name`: `open-webui`
- **Coverage: 90%**
- Missing: endpoints[] → provides[].http-endpoint qualifiers (EXT-A); runtime_manager → runtime_manager_derived; probe_kind → probe_kind_derived

#### `flowise-runtime` — Flowise

- Component: `ai-apps` · Legacy `driver.kind`: `docker-compose-service`
- Goal: `resource_type=runtime` · `action_type=observe` · `tool_type=docker` · branch `n/a (read-only)`
- Provides: `capability_type=http-endpoint × 1` (Flowise) — EXT-A
- Consumes: `ai-stack-compose-running`
- `endpoints[]` (1) → folded into `provides` qualifiers
- Legacy `driver.service_name`: `flowise`
- **Coverage: 90%**
- Missing: endpoints[] → provides[].http-endpoint qualifiers (EXT-A); runtime_manager → runtime_manager_derived; probe_kind → probe_kind_derived

#### `openhands-runtime` — OpenHands

- Component: `ai-apps` · Legacy `driver.kind`: `docker-compose-service`
- Goal: `resource_type=runtime` · `action_type=observe` · `tool_type=docker` · branch `n/a (read-only)`
- Provides: `capability_type=http-endpoint × 1` (OpenHands) — EXT-A
- Consumes: `ai-stack-compose-running`
- `endpoints[]` (1) → folded into `provides` qualifiers
- Legacy `driver.service_name`: `openhands`
- **Coverage: 90%**
- Missing: endpoints[] → provides[].http-endpoint qualifiers (EXT-A); runtime_manager → runtime_manager_derived; probe_kind → probe_kind_derived

#### `n8n-runtime` — n8n

- Component: `ai-apps` · Legacy `driver.kind`: `docker-compose-service`
- Goal: `resource_type=runtime` · `action_type=observe` · `tool_type=docker` · branch `n/a (read-only)`
- Provides: `capability_type=http-endpoint × 1` (n8n) — EXT-A
- Consumes: `ai-stack-compose-running`
- `endpoints[]` (1) → folded into `provides` qualifiers
- Legacy `driver.service_name`: `n8n`
- **Coverage: 90%**
- Missing: endpoints[] → provides[].http-endpoint qualifiers (EXT-A); runtime_manager → runtime_manager_derived; probe_kind → probe_kind_derived

#### `qdrant-runtime` — Qdrant

- Component: `ai-apps` · Legacy `driver.kind`: `docker-compose-service`
- Goal: `resource_type=runtime` · `action_type=observe` · `tool_type=docker` · branch `n/a (read-only)`
- Provides: `capability_type=http-endpoint × 1` (Qdrant) — EXT-A
- Consumes: `ai-stack-compose-running`
- `endpoints[]` (1) → folded into `provides` qualifiers
- Legacy `driver.service_name`: `qdrant`
- **Coverage: 90%**
- Missing: endpoints[] → provides[].http-endpoint qualifiers (EXT-A); runtime_manager → runtime_manager_derived; probe_kind → probe_kind_derived

#### `ollama` — Ollama

- Component: `ai-apps` · Legacy `driver.kind`: `custom-daemon`
- Goal: `resource_type=runtime` · `action_type=converge` · `tool_type=github` · branch `on_absent + on_runtime_diff`
- Provides: `capability_type=http-endpoint × 1` (Ollama API) — EXT-A
- Requires (Predicate AST): `launchd,systemd`
- `endpoints[]` (1) → folded into `provides` qualifiers
- Alt runtime axes: `{'stopped_health': 'Unavailable'}` → `desired_state.alt_runtime`
- Legacy `driver.github_repo`: `ollama/ollama`
- **Coverage: 90%**
- Missing: requires "launchd,systemd" → AST; endpoints[] → provides[].http-endpoint qualifiers (EXT-A); provided_by_tool → provider_provenance_derived; stopped_* axes → desired_state.alt_runtime block

#### `ollama-model-llama3.2` — Ollama llama3.2

- Component: `ai-apps` · Legacy `driver.kind`: `pkg`
- Goal: `resource_type=package` · `action_type=converge` · `tool_type=ollama` · branch `on_absent/on_outdated`
- Consumes: `ollama`
- **Coverage: 80%**
- Missing: provides[].binary.name (no `bin` field)

#### `ollama-model-nomic-embed-text` — Ollama nomic-embed-text

- Component: `ai-apps` · Legacy `driver.kind`: `pkg`
- Goal: `resource_type=package` · `action_type=converge` · `tool_type=ollama` · branch `on_absent/on_outdated`
- Consumes: `ollama`
- **Coverage: 80%**
- Missing: provides[].binary.name (no `bin` field)

#### `ollama-model-qwen3-latest` — Ollama qwen3:latest

- Component: `ai-apps` · Legacy `driver.kind`: `pkg`
- Goal: `resource_type=package` · `action_type=converge` · `tool_type=ollama` · branch `on_absent/on_outdated`
- Consumes: `ollama`
- **Coverage: 80%**
- Missing: provides[].binary.name (no `bin` field)

#### `ollama-model-llama3.1-8b` — Ollama llama3.1:8b

- Component: `ai-apps` · Legacy `driver.kind`: `pkg`
- Goal: `resource_type=package` · `action_type=converge` · `tool_type=ollama` · branch `on_absent/on_outdated`
- Consumes: `ollama`
- **Coverage: 80%**
- Missing: provides[].binary.name (no `bin` field)

#### `ollama-model-mistral-7b` — Ollama mistral:7b

- Component: `ai-apps` · Legacy `driver.kind`: `pkg`
- Goal: `resource_type=package` · `action_type=converge` · `tool_type=ollama` · branch `on_absent/on_outdated`
- Consumes: `ollama`
- **Coverage: 80%**
- Missing: provides[].binary.name (no `bin` field)

#### `ollama-model-qwen2.5-coder-32b` — Ollama qwen2.5-coder:32b

- Component: `ai-apps` · Legacy `driver.kind`: `pkg`
- Goal: `resource_type=package` · `action_type=converge` · `tool_type=ollama` · branch `on_absent/on_outdated`
- Consumes: `ollama`
- **Coverage: 80%**
- Missing: provides[].binary.name (no `bin` field)

#### `ollama-model-llama3.1-70b` — Ollama llama3.1:70b

- Component: `ai-apps` · Legacy `driver.kind`: `pkg`
- Goal: `resource_type=package` · `action_type=converge` · `tool_type=ollama` · branch `on_absent/on_outdated`
- Consumes: `ollama`
- **Coverage: 80%**
- Missing: provides[].binary.name (no `bin` field)

## Component: `ai-python-stack` (25 managed-resources)

#### `pyenv` — pyenv

- Component: `ai-python-stack` · Legacy `driver.kind`: `pyenv-brew`
- Goal: `resource_type=package` · `action_type=converge` · `tool_type=brew` · branch `on_absent`
- **Coverage: 70%**

#### `xz` — XZ Utils

- Component: `ai-python-stack` · Legacy `driver.kind`: `pkg`
- Goal: `resource_type=package` · `action_type=converge` · `tool_type=brew | native-pm` · branch `on_absent/on_outdated`
- Provides: `capability_type=binary, name=xz`
- Update class: `lib` → `policy.update_class`
- **Coverage: 90%**
- Missing: update_class → policy.update_class

#### `python` — Python

- Component: `ai-python-stack` · Legacy `driver.kind`: `pkg`
- Goal: `resource_type=package` · `action_type=converge` · `tool_type=pyenv` · branch `on_absent/on_outdated`
- Consumes: `xz`, `pyenv`
- **Coverage: 80%**
- Missing: provides[].binary.name (no `bin` field)

#### `pip-latest` — pip

- Component: `ai-python-stack` · Legacy `driver.kind`: `pip-bootstrap`
- Goal: `resource_type=config` · `action_type=converge` · `tool_type=pip` · branch `on_absent`
- Provides: `capability_type=os-setting` or `config-file`
- Consumes: `python`
- **Coverage: 70%**
- Missing: desired_state.value (config without desired)

#### `python-venv-available` — Python venv module

- Component: `ai-python-stack` · Legacy `driver.kind`: `capability`
- Goal: `resource_type=capability` · `action_type=observe` · `tool_type=none` · branch `n/a`
- Provides (sonde): `capability_type=python-feature, name=python-venv`
- Probe function: `python_venv_is_available` → `operation_contract.observe.predicate`
- Consumes: `python`
- `operation_contract.observe.evidence`: derived from current `evidence:` block
- Legacy `driver.probe`: `python_venv_is_available`
- **Coverage: 90%**

#### `unsloth` — Unsloth

- Component: `ai-python-stack` · Legacy `driver.kind`: `pip`
- Goal: `resource_type=package` · `action_type=converge` · `tool_type=pip` · branch `on_absent/on_outdated`
- Provides: `capability_type=python-package-set` (unsloth…)
- Isolation: `isolation_type=venv, name=unsloth` (legacy `driver.isolation`)
- Consumes: `python-venv-available`
- Legacy `driver.min_version`: '' (empty placeholder)
- **Coverage: 100%**
- Missing: driver.isolation → operation_contract.execution.isolation_type

#### `unsloth-studio` — Unsloth Studio (launchd)

- Component: `ai-python-stack` · Legacy `driver.kind`: `custom`
- Goal: `resource_type=runtime` · `action_type=converge` · `tool_type=varied` · branch `declared in operation_contract`
- Provides: `capability_type=http-endpoint × 1` (Unsloth Studio) — EXT-A
- Consumes: `unsloth`
- Requires (Predicate AST): `macos`
- `operation_contract.observe.evidence`: derived from current `evidence:` block
- `endpoints[]` (1) → folded into `provides` qualifiers
- **Coverage: 90%**
- Missing: requires "macos" → AST; endpoints[] → provides[].http-endpoint qualifiers (EXT-A); runtime_manager → runtime_manager_derived; probe_kind → probe_kind_derived

#### `unsloth-studio-service` — Unsloth Studio (systemd)

- Component: `ai-python-stack` · Legacy `driver.kind`: `custom`
- Goal: `resource_type=runtime` · `action_type=converge` · `tool_type=varied` · branch `declared in operation_contract`
- Provides: `capability_type=http-endpoint × 1` (Unsloth Studio) — EXT-A
- Consumes: `unsloth`
- Requires (Predicate AST): `linux,wsl2`
- `operation_contract.observe.evidence`: derived from current `evidence:` block
- `endpoints[]` (1) → folded into `provides` qualifiers
- **Coverage: 90%**
- Missing: requires "linux,wsl2" → AST; endpoints[] → provides[].http-endpoint qualifiers (EXT-A); runtime_manager → runtime_manager_derived; probe_kind → probe_kind_derived

#### `pip-group-pytorch` — PyTorch packages

- Component: `ai-python-stack` · Legacy `driver.kind`: `pip`
- Goal: `resource_type=package` · `action_type=converge` · `tool_type=pip` · branch `on_absent/on_outdated`
- Provides: `capability_type=python-package-set` (torch torchvision torchaudio…)
- Isolation: `isolation_type=venv, name=ai-modern` (legacy `driver.isolation`)
- Consumes: `python-venv-available`
- Legacy `driver.min_version`: '' (empty placeholder)
- **Coverage: 100%**
- Missing: driver.isolation → operation_contract.execution.isolation_type

#### `pip-group-huggingface` — Hugging Face packages

- Component: `ai-python-stack` · Legacy `driver.kind`: `pip`
- Goal: `resource_type=package` · `action_type=converge` · `tool_type=pip` · branch `on_absent/on_outdated`
- Provides: `capability_type=python-package-set` (transformers diffusers accelerate datasets tokenizers senten…)
- Isolation: `isolation_type=venv, name=ai-modern` (legacy `driver.isolation`)
- Consumes: `python-venv-available`
- Legacy `driver.min_version`: '' (empty placeholder)
- **Coverage: 100%**
- Missing: driver.isolation → operation_contract.execution.isolation_type

#### `pip-group-langchain` — LangChain packages

- Component: `ai-python-stack` · Legacy `driver.kind`: `pip`
- Goal: `resource_type=package` · `action_type=converge` · `tool_type=pip` · branch `on_absent/on_outdated`
- Provides: `capability_type=python-package-set` (langchain-core>=1.0.0 langchain langchain-community langchai…)
- Isolation: `isolation_type=venv, name=ai-modern` (legacy `driver.isolation`)
- Min version: `1.0.0` → consumes version qualifier (EXT-D)
- Consumes: `python-venv-available`
- Legacy `driver.min_version`: `1.0.0`
- **Coverage: 100%**
- Missing: min_version → consumes version qualifier (EXT-D); driver.isolation → operation_contract.execution.isolation_type

#### `pip-group-llamaindex` — LlamaIndex packages

- Component: `ai-python-stack` · Legacy `driver.kind`: `pip`
- Goal: `resource_type=package` · `action_type=converge` · `tool_type=pip` · branch `on_absent/on_outdated`
- Provides: `capability_type=python-package-set` (llama-index llama-index-llms-ollama llama-index-embeddings-o…)
- Isolation: `isolation_type=venv, name=ai-modern` (legacy `driver.isolation`)
- Consumes: `python-venv-available`
- Legacy `driver.min_version`: '' (empty placeholder)
- **Coverage: 100%**
- Missing: driver.isolation → operation_contract.execution.isolation_type

#### `pip-group-llm-clients` — LLM client packages

- Component: `ai-python-stack` · Legacy `driver.kind`: `pip`
- Goal: `resource_type=package` · `action_type=converge` · `tool_type=pip` · branch `on_absent/on_outdated`
- Provides: `capability_type=python-package-set` (openai anthropic tiktoken…)
- Isolation: `isolation_type=venv, name=ai-modern` (legacy `driver.isolation`)
- Consumes: `python-venv-available`
- Legacy `driver.min_version`: '' (empty placeholder)
- **Coverage: 100%**
- Missing: driver.isolation → operation_contract.execution.isolation_type

#### `pip-group-vector-dbs` — Vector database packages

- Component: `ai-python-stack` · Legacy `driver.kind`: `pip`
- Goal: `resource_type=package` · `action_type=converge` · `tool_type=pip` · branch `on_absent/on_outdated`
- Provides: `capability_type=python-package-set` (chromadb faiss-cpu qdrant-client…)
- Isolation: `isolation_type=venv, name=ai-modern` (legacy `driver.isolation`)
- Consumes: `python-venv-available`
- Legacy `driver.min_version`: '' (empty placeholder)
- **Coverage: 100%**
- Missing: driver.isolation → operation_contract.execution.isolation_type

#### `pip-group-jupyter` — Jupyter packages

- Component: `ai-python-stack` · Legacy `driver.kind`: `pip`
- Goal: `resource_type=package` · `action_type=converge` · `tool_type=pip` · branch `on_absent/on_outdated`
- Provides: `capability_type=python-package-set` (jupyterlab ipywidgets nbformat…)
- Isolation: `isolation_type=venv, name=ai-modern` (legacy `driver.isolation`)
- Consumes: `python-venv-available`
- Legacy `driver.min_version`: '' (empty placeholder)
- **Coverage: 100%**
- Missing: driver.isolation → operation_contract.execution.isolation_type

#### `pip-group-serving` — Serving packages

- Component: `ai-python-stack` · Legacy `driver.kind`: `pip`
- Goal: `resource_type=package` · `action_type=converge` · `tool_type=pip` · branch `on_absent/on_outdated`
- Provides: `capability_type=python-package-set` (fastapi uvicorn gradio…)
- Isolation: `isolation_type=venv, name=ai-modern` (legacy `driver.isolation`)
- Consumes: `python-venv-available`
- Legacy `driver.min_version`: '' (empty placeholder)
- **Coverage: 100%**
- Missing: driver.isolation → operation_contract.execution.isolation_type

#### `pip-group-data-science` — Data science packages

- Component: `ai-python-stack` · Legacy `driver.kind`: `pip`
- Goal: `resource_type=package` · `action_type=converge` · `tool_type=pip` · branch `on_absent/on_outdated`
- Provides: `capability_type=python-package-set` (numpy pandas scipy scikit-learn matplotlib seaborn…)
- Isolation: `isolation_type=venv, name=ai-modern` (legacy `driver.isolation`)
- Consumes: `python-venv-available`
- Legacy `driver.min_version`: '' (empty placeholder)
- **Coverage: 100%**
- Missing: driver.isolation → operation_contract.execution.isolation_type

#### `pip-group-utilities` — Utility packages

- Component: `ai-python-stack` · Legacy `driver.kind`: `pip`
- Goal: `resource_type=package` · `action_type=converge` · `tool_type=pip` · branch `on_absent/on_outdated`
- Provides: `capability_type=python-package-set` (python-dotenv rich tqdm…)
- Isolation: `isolation_type=venv, name=ai-modern` (legacy `driver.isolation`)
- Consumes: `python-venv-available`
- Legacy `driver.min_version`: '' (empty placeholder)
- **Coverage: 100%**
- Missing: driver.isolation → operation_contract.execution.isolation_type

#### `pip-group-dev-tools` — Python dev tools

- Component: `ai-python-stack` · Legacy `driver.kind`: `pip`
- Goal: `resource_type=package` · `action_type=converge` · `tool_type=pip` · branch `on_absent/on_outdated`
- Provides: `capability_type=python-package-set` (ruff…)
- Isolation: `isolation_type=venv, name=ai-modern` (legacy `driver.isolation`)
- Consumes: `python-venv-available`
- Legacy `driver.min_version`: '' (empty placeholder)
- **Coverage: 100%**
- Missing: driver.isolation → operation_contract.execution.isolation_type

#### `pip-group-optimum` — Optimum packages

- Component: `ai-python-stack` · Legacy `driver.kind`: `pip`
- Goal: `resource_type=package` · `action_type=converge` · `tool_type=pip` · branch `on_absent/on_outdated`
- Provides: `capability_type=python-package-set` (optimum…)
- Isolation: `isolation_type=venv, name=ai-modern` (legacy `driver.isolation`)
- Consumes: `python-venv-available`
- Legacy `driver.min_version`: '' (empty placeholder)
- **Coverage: 100%**
- Missing: driver.isolation → operation_contract.execution.isolation_type

#### `pip-group-web-testing` — Web testing packages

- Component: `ai-python-stack` · Legacy `driver.kind`: `pip`
- Goal: `resource_type=package` · `action_type=converge` · `tool_type=pip` · branch `on_absent/on_outdated`
- Provides: `capability_type=python-package-set` (pytest hypothesis beautifulsoup4 playwright mypy coverage…)
- Isolation: `isolation_type=venv, name=ai-modern` (legacy `driver.isolation`)
- Consumes: `python-venv-available`
- Legacy `driver.min_version`: '' (empty placeholder)
- **Coverage: 100%**
- Missing: driver.isolation → operation_contract.execution.isolation_type

#### `pip-group-formal` — Formal verification packages

- Component: `ai-python-stack` · Legacy `driver.kind`: `pip`
- Goal: `resource_type=package` · `action_type=converge` · `tool_type=pip` · branch `on_absent/on_outdated`
- Provides: `capability_type=python-package-set` (z3-solver…)
- Isolation: `isolation_type=venv, name=ai-modern` (legacy `driver.isolation`)
- Consumes: `python-venv-available`
- Legacy `driver.min_version`: '' (empty placeholder)
- **Coverage: 100%**
- Missing: driver.isolation → operation_contract.execution.isolation_type

#### `pip-group-lsp` — LSP server packages

- Component: `ai-python-stack` · Legacy `driver.kind`: `pip`
- Goal: `resource_type=package` · `action_type=converge` · `tool_type=pip` · branch `on_absent/on_outdated`
- Provides: `capability_type=python-package-set` (pygls…)
- Isolation: `isolation_type=venv, name=ai-modern` (legacy `driver.isolation`)
- Consumes: `python-venv-available`
- Legacy `driver.min_version`: '' (empty placeholder)
- **Coverage: 100%**
- Missing: driver.isolation → operation_contract.execution.isolation_type

#### `mps-available` — Metal MPS

- Component: `ai-python-stack` · Legacy `driver.kind`: `capability`
- Goal: `resource_type=capability` · `action_type=observe` · `tool_type=none` · branch `n/a`
- Provides (sonde): `capability_type=hardware-accel, name=mps`
- Probe function: `torch_mps_available` → `operation_contract.observe.predicate`
- Consumes: `pip-group-pytorch`
- Requires (Predicate AST): `macos`
- `operation_contract.observe.evidence`: derived from current `evidence:` block
- Legacy `driver.probe`: `torch_mps_available`
- **Coverage: 90%**
- Missing: requires "macos" → AST

#### `cuda-available` — NVIDIA CUDA

- Component: `ai-python-stack` · Legacy `driver.kind`: `capability`
- Goal: `resource_type=capability` · `action_type=observe` · `tool_type=none` · branch `n/a`
- Provides (sonde): `capability_type=hardware-accel, name=cuda`
- Probe function: `torch_cuda_available` → `operation_contract.observe.predicate`
- Consumes: `pip-group-pytorch`
- Requires (Predicate AST): `linux,wsl2`
- `operation_contract.observe.evidence`: derived from current `evidence:` block
- Legacy `driver.probe`: `torch_cuda_available`
- **Coverage: 90%**
- Missing: requires "linux,wsl2" → AST

## Component: `build-tools` (3 managed-resources)

#### `rustup` — rustup

- Component: `build-tools` · Legacy `driver.kind`: `pkg`
- Goal: `resource_type=package` · `action_type=converge` · `tool_type=brew | curl | native-pm` · branch `on_absent/on_outdated`
- Provides: `capability_type=binary, name=rustup`
- Source: `github_repo=rust-lang/rustup` → `provider_name=github`
- **Coverage: 90%**

#### `rdpilot` — RDPilot

- Component: `build-tools` · Legacy `driver.kind`: `git-repo`
- Goal: `resource_type=package` · `action_type=converge` · `tool_type=git` · branch `on_absent/on_outdated`
- Legacy `driver.github_repo`: `bonomani/rdpilot`
- **Coverage: 70%**

#### `xrdp` — xrdp

- Component: `build-tools` · Legacy `driver.kind`: `pkg`
- Goal: `resource_type=package` · `action_type=converge` · `tool_type=native-pm` · branch `on_absent/on_outdated`
- Provides: `capability_type=binary, name=xrdp`
- Source: `github_repo=neutrinolabs/xrdp` → `provider_name=github`
- Requires (Predicate AST): `linux,wsl2`
- **Coverage: 90%**
- Missing: requires "linux,wsl2" → AST

## Component: `cli-tools` (54 managed-resources)

#### `git` — Git

- Component: `cli-tools` · Legacy `driver.kind`: `pkg`
- Goal: `resource_type=package` · `action_type=converge` · `tool_type=brew | native-pm` · branch `on_absent/on_outdated`
- Provides: `capability_type=binary, name=git`
- **Coverage: 90%**

#### `git-global-config` — Git global config

- Component: `cli-tools` · Legacy `driver.kind`: `git-global`
- Goal: `resource_type=config` · `action_type=converge` · `tool_type=git` · branch `on_drifted`
- Provides: `capability_type=os-setting` or `config-file`
- Consumes: `git`
- **Coverage: 70%**
- Missing: desired_state.value (config without desired)

#### `cli-jq` — jq

- Component: `cli-tools` · Legacy `driver.kind`: `pkg`
- Goal: `resource_type=package` · `action_type=converge` · `tool_type=brew | native-pm` · branch `on_absent/on_outdated`
- Provides: `capability_type=binary, name=jq`
- **Coverage: 90%**

#### `cli-wget` — wget

- Component: `cli-tools` · Legacy `driver.kind`: `pkg`
- Goal: `resource_type=package` · `action_type=converge` · `tool_type=brew | native-pm` · branch `on_absent/on_outdated`
- Provides: `capability_type=binary, name=wget`
- **Coverage: 90%**

#### `cli-curl` — curl

- Component: `cli-tools` · Legacy `driver.kind`: `pkg`
- Goal: `resource_type=package` · `action_type=converge` · `tool_type=brew | native-pm` · branch `on_absent/on_outdated`
- Provides: `capability_type=binary, name=curl`
- **Coverage: 90%**

#### `cli-htop` — htop

- Component: `cli-tools` · Legacy `driver.kind`: `pkg`
- Goal: `resource_type=package` · `action_type=converge` · `tool_type=brew | native-pm` · branch `on_absent/on_outdated`
- Provides: `capability_type=binary, name=htop`
- **Coverage: 90%**

#### `cli-btop` — btop

- Component: `cli-tools` · Legacy `driver.kind`: `pkg`
- Goal: `resource_type=package` · `action_type=converge` · `tool_type=brew | native-pm` · branch `on_absent/on_outdated`
- Provides: `capability_type=binary, name=btop`
- **Coverage: 90%**

#### `cli-tmux` — tmux

- Component: `cli-tools` · Legacy `driver.kind`: `pkg`
- Goal: `resource_type=package` · `action_type=converge` · `tool_type=brew | native-pm` · branch `on_absent/on_outdated`
- Provides: `capability_type=binary, name=tmux`
- **Coverage: 90%**

#### `cli-fzf` — fzf

- Component: `cli-tools` · Legacy `driver.kind`: `pkg`
- Goal: `resource_type=package` · `action_type=converge` · `tool_type=brew | native-pm` · branch `on_absent/on_outdated`
- Provides: `capability_type=binary, name=fzf`
- **Coverage: 90%**

#### `cli-ripgrep` — ripgrep

- Component: `cli-tools` · Legacy `driver.kind`: `pkg`
- Goal: `resource_type=package` · `action_type=converge` · `tool_type=brew | native-pm` · branch `on_absent/on_outdated`
- Provides: `capability_type=binary, name=ripgrep`
- **Coverage: 90%**

#### `cli-fd` — fd

- Component: `cli-tools` · Legacy `driver.kind`: `pkg`
- Goal: `resource_type=package` · `action_type=converge` · `tool_type=brew | native-pm` · branch `on_absent/on_outdated`
- Provides: `capability_type=binary, name=fd`
- **Coverage: 90%**

#### `cli-tree` — tree

- Component: `cli-tools` · Legacy `driver.kind`: `pkg`
- Goal: `resource_type=package` · `action_type=converge` · `tool_type=brew | native-pm` · branch `on_absent/on_outdated`
- Provides: `capability_type=binary, name=tree`
- **Coverage: 90%**

#### `cli-uv` — uv

- Component: `cli-tools` · Legacy `driver.kind`: `pkg`
- Goal: `resource_type=package` · `action_type=converge` · `tool_type=brew | native-pm` · branch `on_absent/on_outdated`
- Provides: `capability_type=binary, name=uv`
- **Coverage: 90%**

#### `cli-pnpm` — pnpm

- Component: `cli-tools` · Legacy `driver.kind`: `pkg`
- Goal: `resource_type=package` · `action_type=converge` · `tool_type=brew | native-pm` · branch `on_absent/on_outdated`
- Provides: `capability_type=binary, name=pnpm`
- **Coverage: 90%**

#### `cli-gcc` — GCC

- Component: `cli-tools` · Legacy `driver.kind`: `pkg`
- Goal: `resource_type=package` · `action_type=converge` · `tool_type=brew | native-pm` · branch `on_absent/on_outdated`
- Provides: `capability_type=binary, name=gcc`
- Update class: `lib` → `policy.update_class`
- **Coverage: 90%**
- Missing: update_class → policy.update_class

#### `cli-gh` — GitHub CLI

- Component: `cli-tools` · Legacy `driver.kind`: `pkg`
- Goal: `resource_type=package` · `action_type=converge` · `tool_type=brew | native-pm` · branch `on_absent/on_outdated`
- Provides: `capability_type=binary, name=gh`
- **Coverage: 90%**

#### `cli-llama.cpp` — llama.cpp

- Component: `cli-tools` · Legacy `driver.kind`: `pkg`
- Goal: `resource_type=package` · `action_type=converge` · `tool_type=brew | native-pm` · branch `on_absent/on_outdated`
- Provides: `capability_type=binary, name=llama.cpp`
- **Coverage: 90%**

#### `cli-opencode` — OpenCode

- Component: `cli-tools` · Legacy `driver.kind`: `pkg`
- Goal: `resource_type=package` · `action_type=converge` · `tool_type=brew | npm` · branch `on_absent/on_outdated`
- Provides: `capability_type=binary, name=opencode`
- Source: `github_repo=sst/opencode` → `provider_name=github`
- **Coverage: 90%**

#### `cli-pi` — Pi Coding Agent

- Component: `cli-tools` · Legacy `driver.kind`: `pkg`
- Goal: `resource_type=package` · `action_type=converge` · `tool_type=npm` · branch `on_absent/on_outdated`
- Provides: `capability_type=binary, name=pi`
- Source: `github_repo=mariozechner/pi` → `provider_name=github`
- **Coverage: 90%**

#### `cli-aria2` — aria2

- Component: `cli-tools` · Legacy `driver.kind`: `pkg`
- Goal: `resource_type=package` · `action_type=converge` · `tool_type=brew | native-pm` · branch `on_absent/on_outdated`
- Provides: `capability_type=binary, name=aria2`
- **Coverage: 90%**

#### `cli-cmake` — CMake

- Component: `cli-tools` · Legacy `driver.kind`: `pkg`
- Goal: `resource_type=package` · `action_type=converge` · `tool_type=brew | native-pm` · branch `on_absent/on_outdated`
- Provides: `capability_type=binary, name=cmake`
- **Coverage: 90%**

#### `cli-hyperfine` — hyperfine

- Component: `cli-tools` · Legacy `driver.kind`: `pkg`
- Goal: `resource_type=package` · `action_type=converge` · `tool_type=brew | native-pm` · branch `on_absent/on_outdated`
- Provides: `capability_type=binary, name=hyperfine`
- **Coverage: 90%**

#### `cli-just` — just

- Component: `cli-tools` · Legacy `driver.kind`: `pkg`
- Goal: `resource_type=package` · `action_type=converge` · `tool_type=brew | native-pm` · branch `on_absent/on_outdated`
- Provides: `capability_type=binary, name=just`
- **Coverage: 90%**

#### `cli-watchexec` — watchexec

- Component: `cli-tools` · Legacy `driver.kind`: `pkg`
- Goal: `resource_type=package` · `action_type=converge` · `tool_type=brew | native-pm` · branch `on_absent/on_outdated`
- Provides: `capability_type=binary, name=watchexec`
- **Coverage: 90%**

#### `cli-z3` — Z3 SMT solver

- Component: `cli-tools` · Legacy `driver.kind`: `pkg`
- Goal: `resource_type=package` · `action_type=converge` · `tool_type=brew | native-pm` · branch `on_absent/on_outdated`
- Provides: `capability_type=binary, name=z3`
- **Coverage: 90%**

#### `cli-cvc5` — cvc5 SMT solver

- Component: `cli-tools` · Legacy `driver.kind`: `pkg`
- Goal: `resource_type=package` · `action_type=converge` · `tool_type=brew-cask | github` · branch `on_absent/on_outdated`
- Provides: `capability_type=binary, name=cvc5`
- Source: `github_repo=cvc5/cvc5` → `provider_name=github`
- Consumes: `home-bin-in-path`
- **Coverage: 90%**

#### `cli-coq` — Coq proof assistant

- Component: `cli-tools` · Legacy `driver.kind`: `pkg`
- Goal: `resource_type=package` · `action_type=converge` · `tool_type=brew | native-pm` · branch `on_absent/on_outdated`
- Provides: `capability_type=binary, name=coqc`
- **Coverage: 90%**

#### `cli-clang` — Clang

- Component: `cli-tools` · Legacy `driver.kind`: `pkg`
- Goal: `resource_type=package` · `action_type=converge` · `tool_type=brew | native-pm` · branch `on_absent/on_outdated`
- Provides: `capability_type=binary, name=clang`
- Update class: `lib` → `policy.update_class`
- **Coverage: 90%**
- Missing: update_class → policy.update_class

#### `cli-llvm` — LLVM

- Component: `cli-tools` · Legacy `driver.kind`: `pkg`
- Goal: `resource_type=package` · `action_type=converge` · `tool_type=brew | native-pm` · branch `on_absent/on_outdated`
- Provides: `capability_type=binary, name=llvm-config`
- Update class: `lib` → `policy.update_class`
- **Coverage: 90%**
- Missing: update_class → policy.update_class

#### `cli-lld` — LLD linker

- Component: `cli-tools` · Legacy `driver.kind`: `pkg`
- Goal: `resource_type=package` · `action_type=converge` · `tool_type=brew | native-pm` · branch `on_absent/on_outdated`
- Provides: `capability_type=binary, name=ld.lld`
- Update class: `lib` → `policy.update_class`
- **Coverage: 90%**
- Missing: update_class → policy.update_class

#### `cli-mold` — mold linker

- Component: `cli-tools` · Legacy `driver.kind`: `pkg`
- Goal: `resource_type=package` · `action_type=converge` · `tool_type=brew | native-pm` · branch `on_absent/on_outdated`
- Provides: `capability_type=binary, name=mold`
- **Coverage: 90%**

#### `cli-nasm` — NASM assembler

- Component: `cli-tools` · Legacy `driver.kind`: `pkg`
- Goal: `resource_type=package` · `action_type=converge` · `tool_type=brew | native-pm` · branch `on_absent/on_outdated`
- Provides: `capability_type=binary, name=nasm`
- **Coverage: 90%**

#### `cli-wabt` — WABT (WebAssembly Binary Toolkit)

- Component: `cli-tools` · Legacy `driver.kind`: `pkg`
- Goal: `resource_type=package` · `action_type=converge` · `tool_type=brew | native-pm` · branch `on_absent/on_outdated`
- Provides: `capability_type=binary, name=wat2wasm`
- **Coverage: 90%**

#### `cli-binaryen` — Binaryen (wasm-opt)

- Component: `cli-tools` · Legacy `driver.kind`: `pkg`
- Goal: `resource_type=package` · `action_type=converge` · `tool_type=brew | native-pm` · branch `on_absent/on_outdated`
- Provides: `capability_type=binary, name=wasm-opt`
- **Coverage: 90%**

#### `cli-b3sum` — BLAKE3 (b3sum)

- Component: `cli-tools` · Legacy `driver.kind`: `pkg`
- Goal: `resource_type=package` · `action_type=converge` · `tool_type=brew | native-pm` · branch `on_absent/on_outdated`
- Provides: `capability_type=binary, name=b3sum`
- **Coverage: 90%**

#### `cli-skopeo` — skopeo

- Component: `cli-tools` · Legacy `driver.kind`: `pkg`
- Goal: `resource_type=package` · `action_type=converge` · `tool_type=brew | native-pm` · branch `on_absent/on_outdated`
- Provides: `capability_type=binary, name=skopeo`
- **Coverage: 90%**

#### `cli-pandoc` — Pandoc

- Component: `cli-tools` · Legacy `driver.kind`: `pkg`
- Goal: `resource_type=package` · `action_type=converge` · `tool_type=brew | native-pm` · branch `on_absent/on_outdated`
- Provides: `capability_type=binary, name=pandoc`
- **Coverage: 90%**

#### `cli-graphviz` — Graphviz

- Component: `cli-tools` · Legacy `driver.kind`: `pkg`
- Goal: `resource_type=package` · `action_type=converge` · `tool_type=brew | native-pm` · branch `on_absent/on_outdated`
- Provides: `capability_type=binary, name=dot`
- **Coverage: 90%**

#### `cli-cosign` — cosign (Sigstore)

- Component: `cli-tools` · Legacy `driver.kind`: `pkg`
- Goal: `resource_type=package` · `action_type=converge` · `tool_type=brew | github` · branch `on_absent/on_outdated`
- Provides: `capability_type=binary, name=cosign`
- Source: `github_repo=sigstore/cosign` → `provider_name=github`
- Consumes: `home-bin-in-path`
- **Coverage: 90%**

#### `cli-minisign` — minisign

- Component: `cli-tools` · Legacy `driver.kind`: `pkg`
- Goal: `resource_type=package` · `action_type=converge` · `tool_type=brew | github` · branch `on_absent/on_outdated`
- Provides: `capability_type=binary, name=minisign`
- Source: `github_repo=jedisct1/minisign` → `provider_name=github`
- Consumes: `home-bin-in-path`
- **Coverage: 90%**

#### `cli-bazelisk` — Bazelisk

- Component: `cli-tools` · Legacy `driver.kind`: `pkg`
- Goal: `resource_type=package` · `action_type=converge` · `tool_type=brew | github` · branch `on_absent/on_outdated`
- Provides: `capability_type=binary, name=bazelisk`
- Source: `github_repo=bazelbuild/bazelisk` → `provider_name=github`
- Consumes: `home-bin-in-path`
- **Coverage: 90%**

#### `cli-mdbook` — mdBook

- Component: `cli-tools` · Legacy `driver.kind`: `pkg`
- Goal: `resource_type=package` · `action_type=converge` · `tool_type=brew | github` · branch `on_absent/on_outdated`
- Provides: `capability_type=binary, name=mdbook`
- Source: `github_repo=rust-lang/mdBook` → `provider_name=github`
- Consumes: `home-bin-in-path`
- **Coverage: 90%**

#### `cli-wasmtime` — Wasmtime

- Component: `cli-tools` · Legacy `driver.kind`: `pkg`
- Goal: `resource_type=package` · `action_type=converge` · `tool_type=brew | github` · branch `on_absent/on_outdated`
- Provides: `capability_type=binary, name=wasmtime`
- Source: `github_repo=bytecodealliance/wasmtime` → `provider_name=github`
- Consumes: `home-bin-in-path`
- **Coverage: 90%**

#### `nftables` — nftables

- Component: `cli-tools` · Legacy `driver.kind`: `pkg`
- Goal: `resource_type=package` · `action_type=converge` · `tool_type=native-pm` · branch `on_absent/on_outdated`
- Provides: `capability_type=binary, name=nft`
- Requires (Predicate AST): `linux,wsl2`
- **Coverage: 90%**
- Missing: requires "linux,wsl2" → AST

#### `firewalld` — firewalld

- Component: `cli-tools` · Legacy `driver.kind`: `pkg`
- Goal: `resource_type=package` · `action_type=converge` · `tool_type=native-pm` · branch `on_absent/on_outdated`
- Provides: `capability_type=binary, name=firewall-cmd`
- Consumes: `nftables`
- Requires (Predicate AST): `linux,wsl2`
- **Coverage: 90%**
- Missing: requires "linux,wsl2" → AST

#### `cli-zsh` — zsh

- Component: `cli-tools` · Legacy `driver.kind`: `pkg`
- Goal: `resource_type=package` · `action_type=converge` · `tool_type=brew | native-pm` · branch `on_absent/on_outdated`
- Provides: `capability_type=binary, name=zsh`
- **Coverage: 90%**

#### `oh-my-zsh` — Oh My Zsh

- Component: `cli-tools` · Legacy `driver.kind`: `script-installer`
- Goal: `resource_type=config` · `action_type=converge` · `tool_type=curl` · branch `on_absent`
- Provides: `capability_type=os-setting` or `config-file`
- Consumes: `cli-zsh`
- Legacy `driver.github_repo`: `ohmyzsh/ohmyzsh`
- **Coverage: 70%**
- Missing: desired_state.value (config without desired)

#### `omz-theme-agnoster` — Agnoster theme

- Component: `cli-tools` · Legacy `driver.kind`: `zsh-config`
- Goal: `resource_type=config` · `action_type=converge` · `tool_type=shell-rc` · branch `on_drifted`
- Provides: `capability_type=os-setting` or `config-file`
- Consumes: `oh-my-zsh`
- **Coverage: 70%**
- Missing: desired_state.value (config without desired)

#### `home-bin-in-path` — ~/bin in PATH

- Component: `cli-tools` · Legacy `driver.kind`: `path-export`
- Goal: `resource_type=config` · `action_type=converge` · `tool_type=shell-rc` · branch `on_drifted`
- Provides: `capability_type=os-setting` or `config-file`
- **Coverage: 70%**
- Missing: desired_state.value (config without desired)

#### `ai-healthcheck` — ai-healthcheck

- Component: `cli-tools` · Legacy `driver.kind`: `home-artifact`
- Goal: `resource_type=config` · `action_type=converge` · `tool_type=none` · branch `on_drifted/on_absent`
- Subkind: `script` → `subtype` qualifier (legacy `driver.subkind`)
- Consumes: `home-bin-in-path`
- **Coverage: 70%**

#### `iterm2` — iTerm2

- Component: `cli-tools` · Legacy `driver.kind`: `pkg`
- Goal: `resource_type=package` · `action_type=converge` · `tool_type=brew-cask` · branch `on_absent/on_outdated`
- Provides: `capability_type=binary, name=iterm2`
- Requires (Predicate AST): `macos`
- **Coverage: 90%**
- Missing: requires "macos" → AST

#### `lm-studio` — LM Studio

- Component: `cli-tools` · Legacy `driver.kind`: `pkg`
- Goal: `resource_type=package` · `action_type=converge` · `tool_type=brew-cask` · branch `on_absent/on_outdated`
- Provides: `capability_type=binary, name=lm-studio`
- Requires (Predicate AST): `macos`
- **Coverage: 90%**
- Missing: requires "macos" → AST

#### `vmware-fusion` — VMware Fusion

- Component: `cli-tools` · Legacy `driver.kind`: `pkg`
- Goal: `resource_type=package` · `action_type=converge` · `tool_type=brew-cask` · branch `on_absent/on_outdated`
- Provides: `capability_type=binary, name=vmrun`
- Requires (Predicate AST): `macos`
- **Coverage: 90%**
- Missing: requires "macos" → AST

#### `vmware-workstation` — VMware Workstation (Windows host)

- Component: `cli-tools` · Legacy `driver.kind`: `pkg`
- Goal: `resource_type=package` · `action_type=converge` · `tool_type=winget` · branch `on_absent/on_outdated`
- Requires (Predicate AST): `wsl2`
- **Coverage: 80%**
- Missing: provides[].binary.name (no `bin` field); requires "wsl2" → AST

## Component: `docker` (5 managed-resources)

#### `docker-desktop` — Docker Desktop

- Component: `docker` · Legacy `driver.kind`: `custom`
- Goal: `resource_type=runtime` · `action_type=converge` · `tool_type=varied` · branch `declared in operation_contract`
- Consumes: `homebrew`
- Requires (Predicate AST): `macos`
- `operation_contract.observe.evidence`: derived from current `evidence:` block
- Alt runtime axes: `{'stopped_dependencies': 'DepsReady'}` → `desired_state.alt_runtime`
- `observe_cmd: docker_desktop_observe` → `operation_contract.observe.state_command`
- `actions:` block → folded into `operation_contract.converge.{on_absent, on_outdated}` (legacy)
- **Coverage: 80%**
- Missing: requires "macos" → AST; runtime_manager → runtime_manager_derived; probe_kind → probe_kind_derived; provided_by_tool → provider_provenance_derived; actions.* → operation_contract.converge branches; stopped_* axes → desired_state.alt_runtime block

#### `docker-daemon` — Docker daemon

- Component: `docker` · Legacy `driver.kind`: `custom`
- Goal: `resource_type=runtime` · `action_type=converge` · `tool_type=varied` · branch `declared in operation_contract`
- Consumes: `docker-desktop?macos`
- `operation_contract.observe.evidence`: derived from current `evidence:` block
- Alt runtime axes: `{'stopped_health': 'Unavailable', 'stopped_dependencies': 'DepsReady'}` → `desired_state.alt_runtime`
- `actions:` block → folded into `operation_contract.converge.{on_absent, on_outdated}` (legacy)
- **Coverage: 80%**
- Missing: conditional consumes (`?cond` syntax → condition AST); runtime_manager → runtime_manager_derived; probe_kind → probe_kind_derived; actions.* → operation_contract.converge branches; stopped_* axes → desired_state.alt_runtime block

#### `docker-available` — Docker available

- Component: `docker` · Legacy `driver.kind`: `capability`
- Goal: `resource_type=capability` · `action_type=observe` · `tool_type=none` · branch `n/a`
- Provides (sonde): `capability_type=daemon, name=docker`
- Probe function: `docker_daemon_is_running` → `operation_contract.observe.predicate`
- Consumes: `docker-daemon`
- `operation_contract.observe.evidence`: derived from current `evidence:` block
- Legacy `driver.probe`: `docker_daemon_is_running`
- **Coverage: 90%**

#### `docker-resources` — Docker resources

- Component: `docker` · Legacy `driver.kind`: `custom`
- Goal: `resource_type=config` · `action_type=converge` · `tool_type=varied` · branch `declared in operation_contract`
- Provides: `capability_type=os-setting` or `config-file`
- Resource limits (parameters): `memory_gb=48, cpu_count=10, swap_mib=4096, disk_mib=204800`
- Consumes: `docker-available`
- Requires (Predicate AST): `macos`
- EXT-B: `desired_state.value: { command: 'docker_resources_desired' }`
- `operation_contract.observe.evidence`: derived from current `evidence:` block
- `observe_cmd: docker_resources_observe` → `operation_contract.observe.state_command`
- `actions:` block → folded into `operation_contract.converge.{on_absent, on_outdated}` (legacy)
- **Coverage: 70%**
- Missing: requires "macos" → AST; desired_cmd → desired_state.value command (EXT-B); actions.* → operation_contract.converge branches

#### `docker-privileged-ports` — Privileged port mapping

- Component: `docker` · Legacy `driver.kind`: `custom`
- Goal: `resource_type=config` · `action_type=converge` · `tool_type=varied` · branch `declared in operation_contract`
- Provides: `capability_type=os-setting` or `config-file`
- Consumes: `docker-desktop`
- Requires (Predicate AST): `macos`
- EXT-B: `desired_state.value: { command: 'docker_privileged_ports_desired' }`
- `operation_contract.observe.evidence`: derived from current `evidence:` block
- `observe_cmd: docker_privileged_ports_observe` → `operation_contract.observe.state_command`
- `actions:` block → folded into `operation_contract.converge.{on_absent, on_outdated}` (legacy)
- **Coverage: 70%**
- Missing: requires "macos" → AST; desired_cmd → desired_state.value command (EXT-B); actions.* → operation_contract.converge branches

## Component: `network-services` (5 managed-resources)

#### `networkquality-available` — networkQuality

- Component: `network-services` · Legacy `driver.kind`: `capability`
- Goal: `resource_type=capability` · `action_type=observe` · `tool_type=none` · branch `n/a`
- Provides (sonde): `capability_type=network-probe, name=networkquality`
- Probe function: `networkquality_is_available` → `operation_contract.observe.predicate`
- Requires (Predicate AST): `macos`
- `operation_contract.observe.evidence`: derived from current `evidence:` block
- Legacy `driver.probe`: `networkquality_is_available`
- **Coverage: 90%**
- Missing: requires "macos" → AST

#### `mdns-available` — mDNS/Bonjour

- Component: `network-services` · Legacy `driver.kind`: `capability`
- Goal: `resource_type=capability` · `action_type=observe` · `tool_type=none` · branch `n/a`
- Provides (sonde): `capability_type=service-discovery, name=mdns`
- Probe function: `mdns_is_available` → `operation_contract.observe.predicate`
- `operation_contract.observe.evidence`: derived from current `evidence:` block
- Legacy `driver.probe`: `mdns_is_available`
- **Coverage: 90%**

#### `avahi` — Avahi (mDNS)

- Component: `network-services` · Legacy `driver.kind`: `pkg`
- Goal: `resource_type=package` · `action_type=converge` · `tool_type=native-pm` · branch `on_absent/on_outdated`
- Requires (Predicate AST): `linux,wsl2`
- EXT-B: `desired_state.value: { literal: '@present' }`
- **Coverage: 80%**
- Missing: provides[].binary.name (no `bin` field); requires "linux,wsl2" → AST; desired_value → desired_state.value (EXT-B)

#### `ariaflow-server` — Ariaflow Server

- Component: `network-services` · Legacy `driver.kind`: `service`
- Goal: `resource_type=runtime` · `action_type=converge` · `tool_type=brew` · branch `on_runtime_diff.to_running`
- Provides: `capability_type=http-endpoint × 2` (aria2 RPC, ariaflow API) — EXT-A
- Consumes: `networkquality-available?macos`, `mdns-available`, `avahi?linux,wsl2`
- Requires (Predicate AST): `macos`
- `endpoints[]` (2) → folded into `provides` qualifiers
- **Coverage: 80%**
- Missing: conditional consumes (`?cond` syntax → condition AST); requires "macos" → AST; endpoints[] → provides[].http-endpoint qualifiers (EXT-A)

#### `ariaflow-dashboard` — Ariaflow Dashboard

- Component: `network-services` · Legacy `driver.kind`: `service`
- Goal: `resource_type=runtime` · `action_type=converge` · `tool_type=brew` · branch `on_runtime_diff.to_running`
- Provides: `capability_type=http-endpoint × 1` (ariaflow dashboard) — EXT-A
- Consumes: `mdns-available`
- Requires (Predicate AST): `macos`
- `endpoints[]` (1) → folded into `provides` qualifiers
- **Coverage: 80%**
- Missing: requires "macos" → AST; endpoints[] → provides[].http-endpoint qualifiers (EXT-A)

## Component: `node-stack` (6 managed-resources)

#### `nvm` — nvm

- Component: `node-stack` · Legacy `driver.kind`: `nvm`
- Goal: `resource_type=package` · `action_type=converge` · `tool_type=none` · branch `on_absent`
- Legacy `driver.github_repo`: `nvm-sh/nvm`
- **Coverage: 70%**

#### `node-lts` — Node.js LTS

- Component: `node-stack` · Legacy `driver.kind`: `nvm-version`
- Goal: `resource_type=package` · `action_type=converge` · `tool_type=nvm` · branch `on_absent`
- **Coverage: 70%**

#### `brew-node-unlinked` — Brew node unlinked

- Component: `node-stack` · Legacy `driver.kind`: `brew-unlink`
- Goal: `resource_type=config` · `action_type=converge` · `tool_type=brew` · branch `on_drifted`
- Provides: `capability_type=os-setting` or `config-file`
- Consumes: `node-lts`
- Requires (Predicate AST): `macos`
- **Coverage: 70%**
- Missing: desired_state.value (config without desired); requires "macos" → AST

#### `npm-global-@openai/codex` — Codex CLI

- Component: `node-stack` · Legacy `driver.kind`: `pkg`
- Goal: `resource_type=package` · `action_type=converge` · `tool_type=npm` · branch `on_absent/on_outdated`
- Provides: `capability_type=binary, name=codex`
- Consumes: `node-lts`
- Update class: `lib` → `policy.update_class`
- **Coverage: 90%**
- Missing: update_class → policy.update_class

#### `npm-global-@anthropic-ai/claude-code` — Claude Code CLI

- Component: `node-stack` · Legacy `driver.kind`: `pkg`
- Goal: `resource_type=package` · `action_type=converge` · `tool_type=npm` · branch `on_absent/on_outdated`
- Provides: `capability_type=binary, name=claude-code`
- Consumes: `node-lts`
- **Coverage: 90%**

#### `npm-global-bmad-method` — BMAD Method CLI

- Component: `node-stack` · Legacy `driver.kind`: `pkg`
- Goal: `resource_type=package` · `action_type=converge` · `tool_type=npm` · branch `on_absent/on_outdated`
- Provides: `capability_type=binary, name=bmad-method`
- Consumes: `node-lts`
- **Coverage: 90%**

## Component: `vscode-stack` (10 managed-resources)

#### `vscode` — Visual Studio Code

- Component: `vscode-stack` · Legacy `driver.kind`: `app-bundle`
- Goal: `resource_type=package` · `action_type=converge` · `tool_type=github` · branch `on_outdated`
- Requires (Predicate AST): `macos`
- **Coverage: 70%**
- Missing: requires "macos" → AST

#### `vscode-code-cmd` — VS Code CLI

- Component: `vscode-stack` · Legacy `driver.kind`: `home-artifact`
- Goal: `resource_type=config` · `action_type=converge` · `tool_type=none` · branch `on_drifted/on_absent`
- Subkind: `symlink` → `subtype` qualifier (legacy `driver.subkind`)
- Consumes: `vscode`
- Requires (Predicate AST): `macos`
- **Coverage: 70%**
- Missing: requires "macos" → AST

#### `vscode-settings` — VS Code settings

- Component: `vscode-stack` · Legacy `driver.kind`: `json-merge`
- Goal: `resource_type=config` · `action_type=converge` · `tool_type=none` · branch `on_drifted`
- Provides: `capability_type=os-setting` or `config-file`
- Consumes: `vscode`
- `operation_contract.observe.evidence`: derived from current `evidence:` block
- **Coverage: 70%**
- Missing: desired_state.value (config without desired)

#### `vscode-ext-ms-python.python` — VS Code Python

- Component: `vscode-stack` · Legacy `driver.kind`: `pkg`
- Goal: `resource_type=package` · `action_type=converge` · `tool_type=vscode` · branch `on_absent/on_outdated`
- Consumes: `vscode-code-cmd`
- **Coverage: 80%**
- Missing: provides[].binary.name (no `bin` field)

#### `vscode-ext-ms-python.vscode-pylance` — VS Code Pylance

- Component: `vscode-stack` · Legacy `driver.kind`: `pkg`
- Goal: `resource_type=package` · `action_type=converge` · `tool_type=vscode` · branch `on_absent/on_outdated`
- Consumes: `vscode-code-cmd`
- **Coverage: 80%**
- Missing: provides[].binary.name (no `bin` field)

#### `vscode-ext-ms-toolsai.jupyter` — VS Code Jupyter

- Component: `vscode-stack` · Legacy `driver.kind`: `pkg`
- Goal: `resource_type=package` · `action_type=converge` · `tool_type=vscode` · branch `on_absent/on_outdated`
- Consumes: `vscode-code-cmd`
- **Coverage: 80%**
- Missing: provides[].binary.name (no `bin` field)

#### `vscode-ext-ms-vscode.cpptools` — VS Code C/C++

- Component: `vscode-stack` · Legacy `driver.kind`: `pkg`
- Goal: `resource_type=package` · `action_type=converge` · `tool_type=vscode` · branch `on_absent/on_outdated`
- Consumes: `vscode-code-cmd`
- **Coverage: 80%**
- Missing: provides[].binary.name (no `bin` field)

#### `vscode-ext-continue.continue` — VS Code Continue

- Component: `vscode-stack` · Legacy `driver.kind`: `pkg`
- Goal: `resource_type=package` · `action_type=converge` · `tool_type=vscode` · branch `on_absent/on_outdated`
- Consumes: `vscode-code-cmd`
- **Coverage: 80%**
- Missing: provides[].binary.name (no `bin` field)

#### `vscode-ext-eamodio.gitlens` — VS Code GitLens

- Component: `vscode-stack` · Legacy `driver.kind`: `pkg`
- Goal: `resource_type=package` · `action_type=converge` · `tool_type=vscode` · branch `on_absent/on_outdated`
- Consumes: `vscode-code-cmd`
- **Coverage: 80%**
- Missing: provides[].binary.name (no `bin` field)

#### `vscode-ext-ms-vscode-remote.remote-containers` — VS Code Dev Containers

- Component: `vscode-stack` · Legacy `driver.kind`: `pkg`
- Goal: `resource_type=package` · `action_type=converge` · `tool_type=vscode` · branch `on_absent/on_outdated`
- Consumes: `vscode-code-cmd`
- **Coverage: 80%**
- Missing: provides[].binary.name (no `bin` field)

## Component: `system` (15 managed-resources)

#### `sudo-available` — sudo access

- Component: `system` · Legacy `driver.kind`: `capability`
- Goal: `resource_type=capability` · `action_type=observe` · `tool_type=none` · branch `n/a`
- Provides (sonde): `capability_type=admin-authority, name=sudo`
- Probe function: `sudo_is_available` → `operation_contract.observe.predicate`
- `operation_contract.observe.evidence`: derived from current `evidence:` block
- Legacy `driver.probe`: `sudo_is_available`
- **Coverage: 90%**

#### `pmset-ac-sleep=0` — AC sleep

- Component: `system` · Legacy `driver.kind`: `setting`
- Goal: `resource_type=config` · `action_type=converge` · `tool_type=pmset` · branch `on_drifted`
- Provides: `capability_type=os-setting` or `config-file`
- Setting target: `key=sleep, value=0` → folded into `operation_contract.converge.on_drifted`
- Admin: `consumes admin-authority/sudo`
- EXT-B: `desired_state.value: { literal: '0' }`
- **Coverage: 90%**
- Missing: desired_value → desired_state.value (EXT-B); admin_required → consumes admin-authority/sudo + policy

#### `pmset-disksleep=0` — Disk sleep

- Component: `system` · Legacy `driver.kind`: `setting`
- Goal: `resource_type=config` · `action_type=converge` · `tool_type=pmset` · branch `on_drifted`
- Provides: `capability_type=os-setting` or `config-file`
- Setting target: `key=disksleep, value=0` → folded into `operation_contract.converge.on_drifted`
- Admin: `consumes admin-authority/sudo`
- EXT-B: `desired_state.value: { literal: '0' }`
- **Coverage: 90%**
- Missing: desired_value → desired_state.value (EXT-B); admin_required → consumes admin-authority/sudo + policy

#### `pmset-standby=0` — Standby

- Component: `system` · Legacy `driver.kind`: `setting`
- Goal: `resource_type=config` · `action_type=converge` · `tool_type=pmset` · branch `on_drifted`
- Provides: `capability_type=os-setting` or `config-file`
- Setting target: `key=standby, value=0` → folded into `operation_contract.converge.on_drifted`
- Admin: `consumes admin-authority/sudo`
- EXT-B: `desired_state.value: { literal: '0' }`
- **Coverage: 90%**
- Missing: desired_value → desired_state.value (EXT-B); admin_required → consumes admin-authority/sudo + policy

#### `app-nap=disabled` — App Nap

- Component: `system` · Legacy `driver.kind`: `setting`
- Goal: `resource_type=config` · `action_type=converge` · `tool_type=defaults` · branch `on_drifted`
- Provides: `capability_type=os-setting` or `config-file`
- Setting target: `domain=NSGlobalDomain, key=NSAppSleepDisabled, value=YES` → folded into `operation_contract.converge.on_drifted`
- EXT-B: `desired_state.value: { literal: '1' }`
- **Coverage: 90%**
- Missing: desired_value → desired_state.value (EXT-B)

#### `finder-show-hidden=1` — Finder hidden files

- Component: `system` · Legacy `driver.kind`: `setting`
- Goal: `resource_type=config` · `action_type=converge` · `tool_type=defaults` · branch `on_drifted`
- Provides: `capability_type=os-setting` or `config-file`
- Setting target: `domain=com.apple.finder, key=AppleShowAllFiles, value=true` → folded into `operation_contract.converge.on_drifted`
- EXT-B: `desired_state.value: { literal: '1' }`
- **Coverage: 90%**
- Missing: desired_value → desired_state.value (EXT-B)

#### `show-all-extensions=1` — Filename extensions

- Component: `system` · Legacy `driver.kind`: `setting`
- Goal: `resource_type=config` · `action_type=converge` · `tool_type=defaults` · branch `on_drifted`
- Provides: `capability_type=os-setting` or `config-file`
- Setting target: `domain=NSGlobalDomain, key=AppleShowAllExtensions, value=true` → folded into `operation_contract.converge.on_drifted`
- EXT-B: `desired_state.value: { literal: '1' }`
- **Coverage: 90%**
- Missing: desired_value → desired_state.value (EXT-B)

#### `dock-autohide=1` — Dock auto-hide

- Component: `system` · Legacy `driver.kind`: `setting`
- Goal: `resource_type=config` · `action_type=converge` · `tool_type=defaults` · branch `on_drifted`
- Provides: `capability_type=os-setting` or `config-file`
- Setting target: `domain=com.apple.dock, key=autohide, value=true` → folded into `operation_contract.converge.on_drifted`
- EXT-B: `desired_state.value: { literal: '1' }`
- **Coverage: 90%**
- Missing: desired_value → desired_state.value (EXT-B)

#### `softwareupdate-schedule=on` — Software Update schedule

- Component: `system` · Legacy `driver.kind`: `softwareupdate-schedule`
- Goal: `resource_type=config` · `action_type=converge` · `tool_type=softwareupdate` · branch `on_drifted`
- Provides: `capability_type=os-setting` or `config-file`
- Admin: `consumes admin-authority/sudo`
- EXT-B: `desired_state.value: { literal: 'on' }`
- **Coverage: 70%**
- Missing: desired_value → desired_state.value (EXT-B); admin_required → consumes admin-authority/sudo + policy

#### `softwareupdate-auto-check=1` — Automatic update checks

- Component: `system` · Legacy `driver.kind`: `setting`
- Goal: `resource_type=config` · `action_type=converge` · `tool_type=defaults` · branch `on_drifted`
- Provides: `capability_type=os-setting` or `config-file`
- Setting target: `domain=${softwareupdate_domain}, key=AutomaticCheckEnabled, value=1` → folded into `operation_contract.converge.on_drifted`
- Admin: `consumes admin-authority/sudo`
- EXT-B: `desired_state.value: { literal: '1' }`
- **Coverage: 90%**
- Missing: desired_value → desired_state.value (EXT-B); admin_required → consumes admin-authority/sudo + policy

#### `softwareupdate-auto-download=1` — Automatic update downloads

- Component: `system` · Legacy `driver.kind`: `setting`
- Goal: `resource_type=config` · `action_type=converge` · `tool_type=defaults` · branch `on_drifted`
- Provides: `capability_type=os-setting` or `config-file`
- Setting target: `domain=${softwareupdate_domain}, key=AutomaticDownload, value=1` → folded into `operation_contract.converge.on_drifted`
- Admin: `consumes admin-authority/sudo`
- EXT-B: `desired_state.value: { literal: '1' }`
- **Coverage: 90%**
- Missing: desired_value → desired_state.value (EXT-B); admin_required → consumes admin-authority/sudo + policy

#### `softwareupdate-auto-install-macos=1` — Automatic macOS updates

- Component: `system` · Legacy `driver.kind`: `setting`
- Goal: `resource_type=config` · `action_type=converge` · `tool_type=defaults` · branch `on_drifted`
- Provides: `capability_type=os-setting` or `config-file`
- Setting target: `domain=${softwareupdate_domain}, key=AutomaticallyInstallMacOSUpdates, value=1` → folded into `operation_contract.converge.on_drifted`
- Admin: `consumes admin-authority/sudo`
- EXT-B: `desired_state.value: { literal: '1' }`
- **Coverage: 90%**
- Missing: desired_value → desired_state.value (EXT-B); admin_required → consumes admin-authority/sudo + policy

#### `softwareupdate-config-data=1` — Configuration data updates

- Component: `system` · Legacy `driver.kind`: `setting`
- Goal: `resource_type=config` · `action_type=converge` · `tool_type=defaults` · branch `on_drifted`
- Provides: `capability_type=os-setting` or `config-file`
- Setting target: `domain=${softwareupdate_domain}, key=ConfigDataInstall, value=1` → folded into `operation_contract.converge.on_drifted`
- Admin: `consumes admin-authority/sudo`
- EXT-B: `desired_state.value: { literal: '1' }`
- **Coverage: 90%**
- Missing: desired_value → desired_state.value (EXT-B); admin_required → consumes admin-authority/sudo + policy

#### `softwareupdate-critical-updates=1` — Security updates

- Component: `system` · Legacy `driver.kind`: `setting`
- Goal: `resource_type=config` · `action_type=converge` · `tool_type=defaults` · branch `on_drifted`
- Provides: `capability_type=os-setting` or `config-file`
- Setting target: `domain=${softwareupdate_domain}, key=CriticalUpdateInstall, value=1` → folded into `operation_contract.converge.on_drifted`
- Admin: `consumes admin-authority/sudo`
- EXT-B: `desired_state.value: { literal: '1' }`
- **Coverage: 90%**
- Missing: desired_value → desired_state.value (EXT-B); admin_required → consumes admin-authority/sudo + policy

#### `system-composition` — System composition

- Component: `system` · Legacy `driver.kind`: `custom`
- Goal: `resource_type=config` · `action_type=converge` · `tool_type=varied` · branch `declared in operation_contract`
- Provides: `capability_type=os-setting` or `config-file`
- Consumes: `sudo-available`, `pmset-ac-sleep=0`, `pmset-disksleep=0`, `pmset-standby=0`, `app-nap=disabled` …
- `operation_contract.observe.evidence`: derived from current `evidence:` block
- **Coverage: 70%**
- Missing: explicit operation_contract for custom; desired_state.value (config without desired)

## Component: `linux-system` (3 managed-resources)

#### `cgroup2-available` — cgroup v2 (unified hierarchy)

- Component: `linux-system` · Legacy `driver.kind`: `capability`
- Goal: `resource_type=capability` · `action_type=observe` · `tool_type=none` · branch `n/a`
- Provides (sonde): `capability_type=kernel-feature, name=cgroup2`
- Probe function: `cgroup2_is_available` → `operation_contract.observe.predicate`
- Requires (Predicate AST): `linux,wsl2`
- `operation_contract.observe.evidence`: derived from current `evidence:` block
- Legacy `driver.probe`: `cgroup2_is_available`
- **Coverage: 90%**
- Missing: requires "linux,wsl2" → AST

#### `systemd-available` — systemd (PID 1)

- Component: `linux-system` · Legacy `driver.kind`: `capability`
- Goal: `resource_type=capability` · `action_type=observe` · `tool_type=none` · branch `n/a`
- Provides (sonde): `capability_type=init-system, name=systemd`
- Probe function: `systemd_is_available` → `operation_contract.observe.predicate`
- Requires (Predicate AST): `linux,wsl2`
- `operation_contract.observe.evidence`: derived from current `evidence:` block
- Legacy `driver.probe`: `systemd_is_available`
- **Coverage: 90%**
- Missing: requires "linux,wsl2" → AST

#### `user-linger-enabled` — user systemd linger

- Component: `linux-system` · Legacy `driver.kind`: `capability`
- Goal: `resource_type=capability` · `action_type=observe` · `tool_type=none` · branch `n/a`
- Provides (sonde): `capability_type=user-service, name=user-linger-enabled`
- Probe function: `user_linger_is_enabled` → `operation_contract.observe.predicate`
- Consumes: `systemd-available`
- Requires (Predicate AST): `linux,wsl2`
- `operation_contract.observe.evidence`: derived from current `evidence:` block
- Legacy `driver.probe`: `user_linger_is_enabled`
- **Coverage: 90%**
- Missing: requires "linux,wsl2" → AST

## Verification Tests (23)

All `tic/**/*.yaml` tests mapped onto `element_type: verification-test`.
Each test has a `verifies[]` list pointing at a managed resource or its
provided capability.

#### `ollama-model-loadable`

- Component: `ai-apps` · Suite: `None` · File: `tic/software/integration.yaml`
- Intent: Ollama must be able to load a model for inference
- Goal `oracle:` → `operation_contract.observe.predicate` of the verification-test: `ollama_model_loadable`
- Legacy `trace:` → structured `verifies[]` relation pointing at the resource being proven (M12)
- Conditional skip: `_tic_ollama_not_running` → `condition` AST (M2)
- **Coverage: 80%**
- Missing: trace → structured verifies relation (M12); skip_when string → AST

#### `docker-compose-services-healthy`

- Component: `ai-apps` · Suite: `None` · File: `tic/software/integration.yaml`
- Intent: Docker Compose services must report healthy status
- Goal `oracle:` → `operation_contract.observe.predicate` of the verification-test: `docker_compose_services_healthy`
- Legacy `trace:` → structured `verifies[]` relation pointing at the resource being proven (M12)
- Conditional skip: `_tic_no_running_compose_services` → `condition` AST (M2)
- **Coverage: 80%**
- Missing: trace → structured verifies relation (M12); skip_when string → AST

#### `pytorch-mps-usable`

- Component: `ai-python-stack` · Suite: `None` · File: `tic/software/integration.yaml`
- Intent: PyTorch MPS backend must be usable for GPU acceleration
- Goal `oracle:` → `operation_contract.observe.predicate` of the verification-test: `torch_mps_available`
- Legacy `trace:` → structured `verifies[]` relation pointing at the resource being proven (M12)
- Conditional skip: `_tic_not_macos` → `condition` AST (M2)
- **Coverage: 80%**
- Missing: trace → structured verifies relation (M12); skip_when string → AST

#### `vscode-python-extension-active`

- Component: `dev-tools` · Suite: `None` · File: `tic/software/integration.yaml`
- Intent: VS Code Python extension must be installed and active
- Goal `oracle:` → `operation_contract.observe.predicate` of the verification-test: `vscode_extension_installed ms-python.python`
- Legacy `trace:` → structured `verifies[]` relation pointing at the resource being proven (M12)
- Conditional skip: `is_not_installed code` → `condition` AST (M2)
- **Coverage: 80%**
- Missing: trace → structured verifies relation (M12); skip_when string → AST

#### `node-via-nvm`

- Component: `dev-tools` · Suite: `None` · File: `tic/software/integration.yaml`
- Intent: Node.js must be managed by nvm, not Homebrew
- Goal `oracle:` → `operation_contract.observe.predicate` of the verification-test: `node_via_nvm_check`
- Legacy `trace:` → structured `verifies[]` relation pointing at the resource being proven (M12)
- Conditional skip: `is_not_installed node` → `condition` AST (M2)
- **Coverage: 80%**
- Missing: trace → structured verifies relation (M12); skip_when string → AST

#### `langchain-ollama-integration`

- Component: `ai-python-stack` · Suite: `None` · File: `tic/software/integration.yaml`
- Intent: langchain-ollama must be importable (bridges LangChain to local Ollama)
- Goal `oracle:` → `operation_contract.observe.predicate` of the verification-test: `python3_module_importable langchain_ollama`
- Legacy `trace:` → structured `verifies[]` relation pointing at the resource being proven (M12)
- Conditional skip: `is_not_installed python3` → `condition` AST (M2)
- **Coverage: 80%**
- Missing: trace → structured verifies relation (M12); skip_when string → AST

#### `torch-importable`

- Component: `ai-python-stack` · Suite: `None` · File: `tic/software/verify.yaml`
- Intent: torch must be importable
- Goal `oracle:` → `operation_contract.observe.predicate` of the verification-test: `python3_module_importable torch`
- Legacy `trace:` → structured `verifies[]` relation pointing at the resource being proven (M12)
- **Coverage: 90%**
- Missing: trace → structured verifies relation (M12)

#### `transformers-importable`

- Component: `ai-python-stack` · Suite: `None` · File: `tic/software/verify.yaml`
- Intent: transformers must be importable
- Goal `oracle:` → `operation_contract.observe.predicate` of the verification-test: `python3_module_importable transformers`
- Legacy `trace:` → structured `verifies[]` relation pointing at the resource being proven (M12)
- **Coverage: 90%**
- Missing: trace → structured verifies relation (M12)

#### `langchain-importable`

- Component: `ai-python-stack` · Suite: `None` · File: `tic/software/verify.yaml`
- Intent: langchain must be importable
- Goal `oracle:` → `operation_contract.observe.predicate` of the verification-test: `python3_module_importable langchain`
- Legacy `trace:` → structured `verifies[]` relation pointing at the resource being proven (M12)
- **Coverage: 90%**
- Missing: trace → structured verifies relation (M12)

#### `langchain-core-version`

- Component: `ai-python-stack` · Suite: `None` · File: `tic/software/verify.yaml`
- Intent: langchain-core must be >=1.0.0 (required by langgraph and langchain-ollama)
- Goal `oracle:` → `operation_contract.observe.predicate` of the verification-test: `pip_package_min_version "langchain-core" "1.0.0"`
- Legacy `trace:` → structured `verifies[]` relation pointing at the resource being proven (M12)
- **Coverage: 90%**
- Missing: trace → structured verifies relation (M12)

#### `unsloth-importable`

- Component: `ai-python-stack` · Suite: `None` · File: `tic/software/verify.yaml`
- Intent: unsloth Python package is not importable on Apple Silicon (NVIDIA/AMD only)
- Goal `oracle:` → `operation_contract.observe.predicate` of the verification-test: `python3_module_importable unsloth`
- Legacy `trace:` → structured `verifies[]` relation pointing at the resource being proven (M12)
- Static skip: `not importable on Apple Silicon (NVIDIA only) — Studio runs in its own venv` → `relation_effect=skip` with reason
- Conditional skip: `_tic_is_macos` → `condition` AST (M2)
- **Coverage: 80%**
- Missing: trace → structured verifies relation (M12); skip_when string → AST

#### `cmake-installed`

- Component: `dev-tools` · Suite: `None` · File: `tic/software/verify.yaml`
- Intent: cmake must be present (required for Unsloth GGUF inference)
- Goal `oracle:` → `operation_contract.observe.predicate` of the verification-test: `is_installed cmake`
- Legacy `trace:` → structured `verifies[]` relation pointing at the resource being proven (M12)
- **Coverage: 90%**
- Missing: trace → structured verifies relation (M12)

#### `open-webui-health`

- Component: `ai-apps` · Suite: `None` · File: `tic/software/verify.yaml`
- Intent: Open WebUI must be accessible on port 3000
- Goal `oracle:` → `operation_contract.observe.predicate` of the verification-test: `http_probe_localhost 3000`
- Legacy `trace:` → structured `verifies[]` relation pointing at the resource being proven (M12)
- Conditional skip: `_tic_service_not_running "open-webui"` → `condition` AST (M2)
- **Coverage: 80%**
- Missing: trace → structured verifies relation (M12); skip_when string → AST

#### `flowise-health`

- Component: `ai-apps` · Suite: `None` · File: `tic/software/verify.yaml`
- Intent: Flowise must be accessible on port 3001
- Goal `oracle:` → `operation_contract.observe.predicate` of the verification-test: `http_probe_localhost 3001`
- Legacy `trace:` → structured `verifies[]` relation pointing at the resource being proven (M12)
- Conditional skip: `_tic_service_not_running "flowise"` → `condition` AST (M2)
- **Coverage: 80%**
- Missing: trace → structured verifies relation (M12); skip_when string → AST

#### `openhands-health`

- Component: `ai-apps` · Suite: `None` · File: `tic/software/verify.yaml`
- Intent: OpenHands must be accessible on port 3002
- Goal `oracle:` → `operation_contract.observe.predicate` of the verification-test: `http_probe_localhost 3002`
- Legacy `trace:` → structured `verifies[]` relation pointing at the resource being proven (M12)
- Conditional skip: `_tic_service_not_running "openhands"` → `condition` AST (M2)
- **Coverage: 80%**
- Missing: trace → structured verifies relation (M12); skip_when string → AST

#### `n8n-health`

- Component: `ai-apps` · Suite: `None` · File: `tic/software/verify.yaml`
- Intent: n8n must be accessible on port 5678
- Goal `oracle:` → `operation_contract.observe.predicate` of the verification-test: `http_probe_localhost 5678`
- Legacy `trace:` → structured `verifies[]` relation pointing at the resource being proven (M12)
- Conditional skip: `_tic_service_not_running "n8n"` → `condition` AST (M2)
- **Coverage: 80%**
- Missing: trace → structured verifies relation (M12); skip_when string → AST

#### `qdrant-health`

- Component: `ai-apps` · Suite: `None` · File: `tic/software/verify.yaml`
- Intent: Qdrant must be accessible on port 6333
- Goal `oracle:` → `operation_contract.observe.predicate` of the verification-test: `http_probe_localhost 6333`
- Legacy `trace:` → structured `verifies[]` relation pointing at the resource being proven (M12)
- Conditional skip: `_tic_service_not_running "qdrant"` → `condition` AST (M2)
- **Coverage: 80%**
- Missing: trace → structured verifies relation (M12); skip_when string → AST

#### `system-composition-converged`

- Component: `system` · Suite: `{'component': 'system', 'ucc_target': 'system-composition', 'role': 'post-convergence verification evidence'}` · File: `tic/system/verify.yaml`
- Intent: system-composition must converge before system verification is accepted
- Goal `oracle:` → `operation_contract.observe.predicate` of the verification-test: `_tic_target_status_is "system-composition" "ok"`
- Legacy `trace:` → structured `verifies[]` relation pointing at the resource being proven (M12)
- Status precondition: `system-composition` → `consumes managed-resource-status:system-composition`
- **Coverage: 90%**
- Missing: trace → structured verifies relation (M12)

#### `homebrew-installed`

- Component: `system` · Suite: `{'component': 'system', 'ucc_target': 'system-composition', 'role': 'post-convergence verification evidence'}` · File: `tic/system/verify.yaml`
- Intent: Homebrew package manager must be installed
- Goal `oracle:` → `operation_contract.observe.predicate` of the verification-test: `is_installed brew`
- Legacy `trace:` → structured `verifies[]` relation pointing at the resource being proven (M12)
- **Coverage: 90%**
- Missing: trace → structured verifies relation (M12)

#### `python3-available`

- Component: `system` · Suite: `{'component': 'system', 'ucc_target': 'system-composition', 'role': 'post-convergence verification evidence'}` · File: `tic/system/verify.yaml`
- Intent: Python 3 must be available for AI stack
- Goal `oracle:` → `operation_contract.observe.predicate` of the verification-test: `is_installed python3`
- Legacy `trace:` → structured `verifies[]` relation pointing at the resource being proven (M12)
- **Coverage: 90%**
- Missing: trace → structured verifies relation (M12)

#### `git-available`

- Component: `system` · Suite: `{'component': 'system', 'ucc_target': 'system-composition', 'role': 'post-convergence verification evidence'}` · File: `tic/system/verify.yaml`
- Intent: Git must be available
- Goal `oracle:` → `operation_contract.observe.predicate` of the verification-test: `is_installed git`
- Legacy `trace:` → structured `verifies[]` relation pointing at the resource being proven (M12)
- **Coverage: 90%**
- Missing: trace → structured verifies relation (M12)

#### `docker-desktop-running`

- Component: `system` · Suite: `{'component': 'system', 'ucc_target': 'system-composition', 'role': 'post-convergence verification evidence'}` · File: `tic/system/verify.yaml`
- Intent: Docker Desktop must be running to execute AI apps
- Goal `oracle:` → `operation_contract.observe.predicate` of the verification-test: `docker_daemon_is_running`
- Legacy `trace:` → structured `verifies[]` relation pointing at the resource being proven (M12)
- Conditional skip: `is_not_installed docker` → `condition` AST (M2)
- **Coverage: 80%**
- Missing: trace → structured verifies relation (M12); skip_when string → AST

#### `ollama-api-reachable`

- Component: `system` · Suite: `{'component': 'system', 'ucc_target': 'system-composition', 'role': 'post-convergence verification evidence'}` · File: `tic/system/verify.yaml`
- Intent: Ollama API must be reachable for local LLM inference
- Goal `oracle:` → `operation_contract.observe.predicate` of the verification-test: `http_probe_localhost 11434`
- Legacy `trace:` → structured `verifies[]` relation pointing at the resource being proven (M12)
- Conditional skip: `_tic_ollama_not_running` → `condition` AST (M2)
- **Coverage: 80%**
- Missing: trace → structured verifies relation (M12); skip_when string → AST

## Preflight Gates (1)

#### `supported-platform`

- Source: `defaults/gates.yaml`
- Goal: `element_type: preflight-gate`, `gate_scope: global`, `class: readiness`
- Condition fn: `_gate_supported_platform` → `Predicate` AST (M2)
- Legacy `target_state:` `host installation_state=Configured` → `desired_state` block on the gate
- Blocking: `hard` → `relation_effect: block-run`
- **Coverage: 80%**
- Missing: target_state → typed desired_state; condition fn → Predicate AST

---

## Summary

- **Managed resources mapped**: 147
- **Verification tests mapped**: 23
- **Preflight gates mapped**: 1
- **Components covered**: 11
- **Average resource coverage**: 86%
- **Min**: 70%  · **Max**: 100%

### Coverage distribution (managed resources)

| Coverage | Resources |
|---:|---:|
| 70–79% | 24 |
| 80–89% | 22 |
| 90–99% | 85 |
| 100–109% | 16 |

### Per-component coverage

| Component | Resources | Avg coverage |
|---|---:|---:|
| `software-bootstrap` | 5 | 76% |
| `ai-apps` | 16 | 82% |
| `ai-python-stack` | 25 | 94% |
| `build-tools` | 3 | 83% |
| `cli-tools` | 54 | 88% |
| `docker` | 5 | 78% |
| `network-services` | 5 | 84% |
| `node-stack` | 6 | 80% |
| `vscode-stack` | 10 | 77% |
| `system` | 15 | 87% |
| `linux-system` | 3 | 90% |

### Most common missing items (validator's TODO list)

| Missing | Resources affected |
|---|---:|
| requires <string> → AST | 29 |
| provides[].binary.name (no `bin` field) | 17 |
| driver.isolation → operation_contract.execution.isolation_type | 16 |
| desired_value → desired_state.value (EXT-B) | 15 |
| endpoints[] → provides[].http-endpoint qualifiers (EXT-A) | 10 |
| desired_state.value (config without desired) | 9 |
| runtime_manager → runtime_manager_derived | 9 |
| probe_kind → probe_kind_derived | 9 |
| admin_required → consumes admin-authority/sudo + policy | 9 |
| update_class → policy.update_class | 6 |
| actions.* → operation_contract.converge branches | 6 |
| provided_by_tool → provider_provenance_derived | 5 |
| stopped_* axes → desired_state.alt_runtime block | 3 |
| conditional consumes (`?cond` syntax → condition AST) | 3 |
| desired_cmd → desired_state.value command (EXT-B) | 2 |
| state_model written explicitly → must equal state_model_derived | 1 |
| min_version → consumes version qualifier (EXT-D) | 1 |
| explicit operation_contract for custom | 1 |

### Migration phase impact

| Resource subset | # | Phases needed |
|---|---:|---|
| `pkg`-driven packages | 71 | M1, M2, M3, M5, M6 |
| `pip`-driven groups | 16 | M1, M2, M5, M11 (EXT-E) |
| `setting` configs | 12 | M5, M7, M9 (EXT-B), Configuration section |
| `capability` probes | 11 | M1, M11 |
| `custom` resources | 10 | M5, M7 |
| Docker / compose | 7 | M5, M7, virtualization pattern |
| Resources with endpoints | 10 | M8 (EXT-A) |
| Resources with desired_value/cmd | 17 | M9 (EXT-B) |
| Resources with min_version | 1 | M10b (EXT-D) |
| Resources with stopped_* axes | 3 | M9 (alt runtime axes in desired_state) |
| Resources with isolation block | 16 | M7 (operation_contract.execution.isolation_type) |
| Resources with update_class | 6 | M7 (policy.update_class) |
| Resources with admin_required | 9 | M7 (policy + consumes admin-authority/sudo) |
| Resources with actions: | 6 | M7 (folded into converge.*) |
| Resources with runtime_manager | 9 | M11 (`_derived` field) |
| Resources with probe_kind | 9 | M11 (`_derived` field) |
| Resources with provided_by_tool | 5 | M11 (`_derived` field) |
| Verification tests with trace: | 23 | M12 (structured verifies) |
| Verification tests with skip_when: | 14 | M2 (condition AST) |
| Preflight gates with condition fn: | 1 | M2 (condition AST) |
