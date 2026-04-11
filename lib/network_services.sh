#!/usr/bin/env bash
# lib/network_services.sh — network services runner (ariaflow)

# Usage: run_network_services_from_yaml <cfg_dir> <yaml_path>
run_network_services_from_yaml() {
  local cfg_dir="$1" yaml="$2"

  ucc_yaml_capability_target "$cfg_dir" "$yaml" "networkquality-available"
  ucc_yaml_capability_target "$cfg_dir" "$yaml" "mdns-available"
  ucc_yaml_simple_target     "$cfg_dir" "$yaml" "avahi"
  ucc_yaml_runtime_target    "$cfg_dir" "$yaml" "ariaflow-server"
  ucc_yaml_runtime_target    "$cfg_dir" "$yaml" "ariaflow-dashboard"
}
