#!/usr/bin/env bash
# lib/docker.sh — compatibility loader for the Docker library split.
#
# As of 2026-04-28 the Docker library is split by platform/role:
#   lib/docker_common.sh         — portable daemon helpers + dispatcher
#   lib/docker_engine.sh         — Linux/WSL existing-engine support
#   lib/docker_desktop_macos.sh  — macOS Docker Desktop app + launch
#
# This file remains so existing call sites (tests, YAML libs entries) that
# `source lib/docker.sh` continue to work without behavior change.

_ucc_docker_lib_dir="${BASH_SOURCE[0]%/*}"
# shellcheck source=lib/docker_common.sh
source "$_ucc_docker_lib_dir/docker_common.sh"
# shellcheck source=lib/docker_engine.sh
source "$_ucc_docker_lib_dir/docker_engine.sh"
# shellcheck source=lib/docker_desktop_macos.sh
source "$_ucc_docker_lib_dir/docker_desktop_macos.sh"
unset _ucc_docker_lib_dir
