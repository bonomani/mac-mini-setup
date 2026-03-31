# Mac Mini AI Setup - Gaps Analysis

## Overview

This document categorizes identified gaps in the mac-mini-setup framework as either **Bug** (critical issues) or **New Feature** (enhancements deferred to future implementation).

---

## Bugs

### Bug #1: Missing Verification Tests for AI Apps Services
**Type**: Bug  
**Severity**: High  
**Component**: TIC, tic/software/verify.yaml  

**Description**: The `tic/software/verify.yaml` file contains only 7 tests for software-layer verification, but there are 14 components total with many more targets. The AI apps (5 Docker Compose services) are not verified.

**Impact**: No post-convergence verification that AI app services (Open WebUI, Flowise, OpenHands, n8n, Qdrant) are actually running and responding.

**Current State**:
```yaml
# tic/software/verify.yaml - Only 7 tests for entire software layer
tests:
  - name: torch-importable
  - name: transformers-importable
  - name: langchain-importable
  - name: langchain-core-version
  - name: unsloth-importable
  - name: cmake-installed
  # Missing: 5 AI app service health checks
```

**Fix**: Add comprehensive HTTP endpoint probes for each AI app service:
```yaml
- name: open-webui-health
  component: ai-apps
  intent: "Open WebUI must be accessible on port 3000"
  oracle: "curl -fsS --connect-timeout 5 http://localhost:3000 >/dev/null"
  trace: "component:ai-apps / service:open-webui"

- name: flowise-health
  component: ai-apps
  intent: "Flowise must be accessible on port 3001"
  oracle: "curl -fsS --connect-timeout 5 http://localhost:3001 >/dev/null"
  trace: "component:ai-apps / service:flowise"

- name: openhands-health
  component: ai-apps
  intent: "OpenHands must be accessible on port 3002"
  oracle: "curl -fsS --connect-timeout 5 http://localhost:3002 >/dev/null"
  trace: "component:ai-apps / service:openhands"

- name: n8n-health
  component: ai-apps
  intent: "n8n must be accessible on port 5678"
  oracle: "curl -fsS --connect-timeout 5 http://localhost:5678 >/dev/null"
  trace: "component:ai-apps / service:n8n"

- name: qdrant-health
  component: ai-apps
  intent: "Qdrant must be accessible on port 6333"
  oracle: "curl -fsS --connect-timeout 5 http://localhost:6333 >/dev/null"
  trace: "component:ai-apps / service:qdrant"
```

---

### Bug #2: Custom-Daemon Driver Lacks Action Implementation
**Type**: Bug  
**Severity**: Medium  
**Component**: lib/ucc_drivers.sh, drivers/custom_daemon.sh  

**Description**: The `custom-daemon` driver (used for Ollama) only implements observe functionality. There is no install or update action defined, meaning the driver cannot properly manage daemon lifecycle.

**Current State** (lib/ucc_drivers.sh):
```bash
# custom_daemon.sh - Only implements observe
_ucc_driver_custom_daemon_observe() { ... }
# Missing: _ucc_driver_custom_daemon_action
# Missing: _ucc_driver_custom_daemon_evidence
```

**Impact**: Ollama daemon cannot be properly installed, started, or updated through the driver architecture. The current implementation bypasses the driver by using embedded shell code in YAML.

**Fix**: Implement full driver interface for custom-daemon:
```bash
_ucc_driver_custom_daemon_action() {
  local cfg_dir="$1" yaml="$2" target="$3" action="$4"
  local bin plist process
  bin="$(_ucc_yaml_target_driver_get "$cfg_dir" "$yaml" "$target" "bin")"
  plist="$(_ucc_yaml_target_driver_get "$cfg_dir" "$yaml" "$target" "plist")"
  process="$(_ucc_yaml_target_driver_get "$cfg_dir" "$yaml" "$target" "process")"
  
  [[ -n "$bin" ]] || return 1
  
  case "$action" in
    install)
      # Check if daemon is already installed via launchd
      if [[ -n "$plist" ]] && launchctl list | grep -qF "$plist"; then
        log_info "Daemon already installed via launchd"
        return 0
      fi
      # Start daemon in background
      $bin &
      ;;
    update)
      # Restart daemon with updated binary
      if [[ -n "$plist" ]]; then
        launchctl load "$plist"
      else
        pkill -f "$process" || true
        $bin &
      fi
      ;;
  esac
}
```

---

### Bug #3: Compose-File Driver Lacks Install/Update Actions
**Type**: Bug  
**Severity**: High  
**Component**: lib/ucc_drivers.sh, drivers/compose_file.sh  

**Description**: The `compose-file` driver (used for AI apps stack) has no install or update action. According to DRIVER_ARCHITECTURE.md, "compose-file: runtime | ✅ | — | ✅", the action column shows "-" (no-op), but this means the stack definition file can never be created.

**Current State**:
```yaml
# ucc/software/ai-apps.yaml - ai-stack-compose-file target
targets:
  ai-stack-compose-file:
    driver:
      kind: compose-file
      path_env: COMPOSE_FILE
    # No install action defined
```

**Impact**: The Docker Compose stack definition file is created via embedded shell code in ai_apps.sh, bypassing the driver architecture. This violates P1 (YAML is pure data) and P8 (evidence parity).

**Fix**: Implement proper compose-file driver with install/update actions:
```bash
_ucc_driver_compose_file_action() {
  local cfg_dir="$1" yaml="$2" target="$3" action="$4"
  local path_env stack_dir compose_file template
  path_env="$(_ucc_yaml_target_driver_get "$cfg_dir" "$yaml" "$target" "path_env")"
  
  [[ -n "$path_env" ]] || return 1
  
  # Read stack configuration
  local compose_dir_rel="stack" compose_file_name="docker-compose.yml"
  while IFS= read -r line; do
    case "$line" in
      stack.compose_dir*) compose_dir_rel="${line#stack.compose_dir: }" ;;
      stack.compose_file*) compose_file_name="${line#stack.compose_file: }" ;;
    esac
  done < <(_ucc_yaml_target_get_many "$cfg_dir" "$yaml" "$target" \
    stack.compose_dir stack.compose_file)
  
  COMPOSE_DIR="$HOME/${compose_dir_rel}"
  COMPOSE_FILE="$COMPOSE_DIR/${compose_file_name}"
  template="$cfg_dir/stack/docker-compose.yml"
  
  case "$action" in
    install|update)
      mkdir -p "$COMPOSE_DIR"
      if [[ ! -f "$COMPOSE_FILE" ]] || [[ "$action" == "update" ]]; then
        cp "$template" "$COMPOSE_FILE"
      fi
      ;;
  esac
}
```

---

### Bug #4: TIC Verification Depends on UCC Status File (Circular Dependency)
**Type**: Bug  
**Severity**: High  
**Component**: tic/system/verify.yaml, lib/tic_runner.sh  

**Description**: The `tic/system/verify.yaml` contains only 1 test that depends on the UCC target status file:
```yaml
- name: system-composition-converged
  requires_status_target: system-composition
  oracle: "awk -F'|' '\$1==\"system-composition\" {val=\$2} END {exit !(val==\"ok\")}' \"\${UCC_TARGET_STATUS_FILE:-/dev/null}\""
```

This creates a circular dependency where TIC verification depends on UCC status but doesn't independently verify the actual system state.

**Impact**: If the UCC status file is missing or corrupted, TIC verification fails completely. No independent health checks exist.

**Fix**: Add independent verification tests that don't rely on UCC status:
```yaml
# tic/system/verify.yaml
tests:
  - name: docker-desktop-running
    component: system
    intent: "Docker Desktop must be running to execute AI apps"
    oracle: "docker info >/dev/null 2>&1"
    trace: "component:system / verification:docker-daemon"
  
  - name: ollama-api-reachable
    component: system
    intent: "Ollama API must be reachable for local LLM inference"
    oracle: "curl -fsS http://127.0.0.1:11434/api/tags >/dev/null 2>&1"
    trace: "component:system / verification:ollama-api"
  
  - name: python3-available
    component: system
    intent: "Python 3 must be available for AI stack"
    oracle: "python3 -c 'import sys; assert sys.version_info >= (3, 12)' >/dev/null 2>&1"
    trace: "component:system / verification:python-version"
  
  - name: homebrew-installed
    component: system
    intent: "Homebrew package manager must be installed"
    oracle: "command -v brew >/dev/null 2>&1"
    trace: "component:system / verification:homebrew"
```

---

### Bug #5: ai-healthcheck Script Doesn't Validate Service Health
**Type**: Bug  
**Severity**: Medium  
**Component**: scripts/ai-healthcheck  

**Description**: The current `scripts/ai-healthcheck` script only prints versions and lists containers/models without actually validating that services are responding correctly to requests.

**Current State**:
```bash
#!/bin/bash
echo "=== AI Mac Mini Healthcheck ==="
echo "brew:    $(command -v brew   || echo 'missing')"
echo "python:  $(python3 --version 2>/dev/null || echo 'missing')"
# ... version checks only
echo "--- Docker containers ---"
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
# No actual HTTP health checks!
```

**Impact**: Users cannot determine if services are actually healthy, only if they exist.

**Fix**: Enhance the healthcheck script with actual HTTP probes:
```bash
#!/bin/bash
set -euo pipefail

# Enhanced AI Mac Mini Healthcheck
echo "=== AI Mac Mini Healthcheck ==="

# Core tools check
echo "--- Core Tools ---"
printf "%-15s %s\n" "brew:" "$(command -v brew || echo 'MISSING')"
printf "%-15s %s\n" "python:" "$(python3 --version 2>/dev/null || echo 'MISSING')"
printf "%-15s %s\n" "node:" "$(node --version 2>/dev/null || echo 'MISSING')"
printf "%-15s %s\n" "docker:" "$(docker --version 2>/dev/null || echo 'MISSING')"

# Docker daemon health
echo ""
echo "--- Docker Daemon ---"
if docker info >/dev/null 2>&1; then
  echo "Status: HEALTHY"
  docker ps --format 'table {{.Names}}\t{{.Status}}' 2>/dev/null || echo "No containers running"
else
  echo "Status: UNHEALTHY - Docker daemon not responding"
fi

# Ollama API health
echo ""
echo "--- Ollama API ---"
if curl -fsS --connect-timeout 5 http://127.0.0.1:11434/api/tags >/dev/null 2>&1; then
  echo "Status: HEALTHY"
  echo "Models:"
  curl -s http://127.0.0.1:11434/api/tags | jq -r '.models[].name' 2>/dev/null || echo "Unable to parse models"
else
  echo "Status: UNHEALTHY - Ollama API not reachable"
fi

# AI Apps health
echo ""
echo "--- AI Apps ---"

check_app() {
  local name="$1" port="$2"
  if curl -fsS --connect-timeout 5 "http://localhost:$port" >/dev/null 2>&1; then
    printf "%-15s HEALTHY\n" "${name}:"
  else
    printf "%-15s UNHEALTHY (port $port not responding)\n" "${name}:"
  fi
}

check_app "Open WebUI"    3000
check_app "Flowise"       3001
check_app "OpenHands"     3002
check_app "n8n"           5678
check_app "Qdrant"        6333

# Summary
echo ""
echo "--- Summary ---"
total=0 healthy=0 unhealthy=0

for app in "Open WebUI:3000" "Flowise:3001" "OpenHands:3002" "n8n:5678" "Qdrant:6333"; do
  total=$((total + 1))
  name="${app%%:*}"
  port="${app##*:}"
  if curl -fsS --connect-timeout 5 "http://localhost:$port" >/dev/null 2>&1; then
    healthy=$((healthy + 1))
  else
    unhealthy=$((unhealthy + 1))
  fi
done

echo "AI Apps: $healthy/$total healthy"
[[ $unhealthy -eq 0 ]] || exit 1
```

---

### Bug #6: Missing Dependency Chain Verification Tests
**Type**: Bug  
**Severity**: Low  
**Component**: tic/software/verify.yaml, tic/system/verify.yaml  

**Description**: No TIC tests verify that dependency chains are properly established and in the correct order.

**Impact**: The installation could proceed but result in broken dependencies, making debugging difficult for users.

**Fix**: Add dependency verification tests:
```yaml
# tic/software/verify.yaml
tests:
  - name: homebrew-before-git
    component: git
    intent: "Homebrew package manager must be installed before Git"
    oracle: "[[ -x \$(command -v brew) ]] && [[ -x \$(command -v git) ]]"
    trace: "component:git / dependency:brew"
  
  - name: homebrew-before-docker
    component: docker
    intent: "Homebrew package manager must be installed before Docker"
    oracle: "[[ -x \$(command -v brew) ]] && [[ -x \$(command -v docker) ]]"
    trace: "component:docker / dependency:brew"
  
  - name: docker-before-ai-apps
    component: ai-apps
    intent: "Docker must be installed before AI apps"
    oracle: "[[ -x \$(command -v docker) ]] && [[ -x \$(command -v docker-compose) ]]"
    trace: "component:ai-apps / dependency:docker"
  
  - name: python-before-ai-stack
    component: ai-python-stack
    intent: "Python must be installed before AI stack packages"
    oracle: "[[ -x \$(command -v python3) ]] && [[ -d \${PYENV_ROOT:-\$HOME/.pyenv} ]]"
    trace: "component:ai-python-stack / dependency:python"
```

---

## New Features

### Feature #1: Error Recovery and Rollback Testing
**Type**: New Feature  
**Priority**: High  
**Defer To**: Post-initial stability phase  

**Description**: Implement tests that verify the framework handles failures gracefully:
- What happens if a package fails to install?
- What happens if Docker daemon crashes during AI app start?
- Is there a recovery path?

**Implementation Plan**:
1. Create test scenarios for common failure points
2. Implement recovery procedures
3. Add verification tests that run after failure scenarios

```yaml
# tic/system/recovery.yaml (NEW FILE)
tests:
  - name: install-failure-retry
    component: system
    intent: "Failed installation should be retryable"
    oracle: |
      # Simulate failure and verify retry works
      echo "to be implemented"
    skip: "Feature not yet implemented - see Feature #1"
  
  - name: docker-daemon-crash-recovery
    component: ai-apps
    intent: "AI apps should recover when Docker daemon restarts"
    oracle: |
      # Restart docker and verify services come back
      echo "to be implemented"
    skip: "Feature not yet implemented - see Feature #1"
```

---

### Feature #2: Configuration Drift Detection and Auto-Repair
**Type**: New Feature  
**Priority**: Medium  
**Defer To**: Post-initial stability phase  

**Description**: Add periodic tests to detect configuration drift and optionally auto-repair:
- Docker resource settings may be changed by user
- VS Code settings may be modified
- System defaults may change

**Implementation Plan**:
1. Create drift detection tests
2. Implement optional auto-repair mode
3. Add reporting of drifted configurations

```yaml
# tic/system/drift-detection.yaml (NEW FILE)
tests:
  - name: docker-memory-configured
    component: docker-config
    intent: "Docker memory settings should match configuration"
    oracle: "docker info | grep -q 'Memory: 48GiB'"
    drift_report:
      actual_value: "docker info --format '{{.MemTotal}}'"
      desired_value: "48GiB"
    auto_repair: false
    skip: "Feature not yet implemented - see Feature #2"
  
  - name: vscode-settings-intact
    component: dev-tools
    intent: "VS Code settings should match configured values"
    oracle: |
      python3 -c "
      import json
      # Check settings match expected values
      pass
      "
    skip: "Feature not yet implemented - see Feature #2"
```

---

### Feature #3: Comprehensive Integration Testing Framework
**Type**: New Feature  
**Priority**: High  
**Defer To**: Post-initial stability phase  

**Description**: Create end-to-end integration tests that verify:
- Ollama models are properly loaded and accessible
- PyTorch can actually use MPS on Apple Silicon
- Docker Compose services communicate with each other
- VS Code extensions work together

**Implementation Plan**:
1. Create integration test directory structure
2. Implement service interaction tests
3. Add performance benchmarks

```bash
# scripts/integration-tests.sh (NEW FILE)
#!/bin/bash
set -euo pipefail

echo "=== Integration Tests ==="
echo ""

# Test 1: Ollama model download and inference
echo "--- Ollama Model Integration ---"
# Test that llama3.2 model can respond

# Test 2: Docker Compose service communication
echo "--- Docker Compose Integration ---"
# Verify Open WebUI can connect to Ollama

# Test 3: MPS acceleration
echo "--- MPS Acceleration ---"
python3 -c "import torch; assert torch.backends.mps.is_available()"

# Test 4: VS Code extension synergy
echo "--- VS Code Extension Synergy ---"
# Verify Python + Pylance + Jupyter work together

echo ""
echo "Integration tests complete"
```

---

### Feature #4: Performance Testing and Optimization Reporting
**Type**: New Feature  
**Priority**: Low  
**Defer To**: Post-stable release  

**Description**: Add performance metrics and optimization recommendations:
- Timing measurements for each convergence step
- Resource usage monitoring during setup
- Optimization suggestions for slow components

**Implementation Plan**:
1. Add timing instrumentation to UCC
2. Track memory and CPU usage during setup
3. Generate optimization reports

```yaml
# tic/system/performance.yaml (NEW FILE)
tests:
  - name: homebrew-install-time
    component: homebrew
    intent: "Homebrew installation should complete within acceptable time"
    oracle: |
      START=$(date +%s)
      # Measure installation time
      END=$(date +%s)
      DURATION=$((END - START))
      [[ $DURATION -lt 300 ]]  # Less than 5 minutes
    performance:
      threshold: 300 seconds
      optimization_suggestion: >
        Consider using brew cache to speed up subsequent runs
    skip: "Feature not yet implemented - see Feature #4"
```

---

### Feature #5: CI/CD Pipeline Integration
**Type**: New Feature  
**Priority**: Medium  
**Defer To**: Post-initial stability phase  

**Description**: Create GitHub Actions workflow to automatically validate the setup process on each commit.

```yaml
# .github/workflows/test-setup.yml (NEW FILE)
name: AI Setup Tests

on:
  push:
    branches: [main, develop]
  pull_request:

jobs:
  test-installation:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Run pre-installation checks
        run: ./install.sh --preflight
      
      - name: Run full installation (dry-run)
        run: ./install.sh --dry-run
      
      - name: Run verification tests
        run: |
          # Create test environment
          ./install.sh verify
```

---

### Feature #6: Advanced Driver Framework Enhancements
**Type**: New Feature  
**Priority**: Medium  
**Defer To**: Post-initial stability phase  

**Description**: Improve driver framework to support:
- Parameterized drivers with validation
- Driver dependency graph
- Dynamic driver registration

**Implementation Plan**:
1. Add driver parameter schema validation
2. Create driver dependency resolution
3. Implement dynamic driver loading

```bash
# lib/ucc_drivers.sh enhancements (NEW)

# Register a new driver dynamically
register_driver() {
  local kind="$1" observe_fn="$2" action_fn="$3" evidence_fn="$4"
  [[ -n "$kind" ]] || { log_error "Driver kind required"; return 1; }
  
  _UCC_REGISTERED_DRIVERS["${kind}"]="$observe_fn|$action_fn|$evidence_fn"
}

# Validate driver parameters
validate_driver_params() {
  local kind="$1" params="$2"
  # Load driver schema and validate
}

# Resolve driver dependencies
resolve_driver_deps() {
  local kind="$1"
  # Return list of required drivers in correct order
}
```

---

## Summary

### By Category

| Category | Bugs | New Features |
|----------|------|--------------|
| Verification & Tests | 5 | 4 |
| Driver Architecture | 2 | 1 |
| Health & Monitoring | 1 | 2 |
| Error Handling | 0 | 2 |
| Documentation | 1 | 0 |
| **Total** | **9** | **9** |

### Priority Matrix

| Severity | Bugs | New Features |
|----------|------|--------------|
| Critical | 2 | 1 |
| High | 4 | 2 |
| Medium | 3 | 3 |
| Low | 0 | 3 |

### Recommended Implementation Order

1. **Immediate (Phase 1)**:
   - Bug #1: Add AI apps HTTP endpoint verification tests
   - Bug #4: Fix TIC verification circular dependency
   
2. **Short-term (Phase 2)**:
   - Bug #5: Enhance healthcheck script with HTTP probes
   - Feature #1: Error recovery testing framework
   
3. **Medium-term (Phase 3)**:
   - Bug #2 & #3: Fix custom-daemon and compose-file drivers
   - Feature #2: Configuration drift detection
   
4. **Long-term (Phase 4)**:
   - Feature #3: Comprehensive integration testing
   - Feature #4: Performance testing framework