#!/usr/bin/env bash
# github-catalog-lib.sh — shared helpers (exit codes, config, TTY, versions)
# shellcheck shell=bash
[[ -n "${GITHUB_CATALOG_LIB_LOADED:-}" ]] && return 0
GITHUB_CATALOG_LIB_LOADED=1

# Exit-code contract (ADR-003 P1.4) — GC_EXIT_OK is the implicit success (0)
readonly GC_EXIT_OK=0
readonly GC_EXIT_PARTIAL=1
readonly GC_EXIT_USAGE=2
readonly GC_EXIT_PRECOND=3
export GC_EXIT_OK GC_EXIT_PARTIAL GC_EXIT_USAGE GC_EXIT_PRECOND

gc_exit_usage() {
  printf 'ERROR: %s\n' "$*" >&2
  exit "$GC_EXIT_USAGE"
}

gc_exit_precond() {
  printf 'ERROR: %s\n' "$*" >&2
  exit "$GC_EXIT_PRECOND"
}

gc_exit_partial() {
  printf 'ERROR: %s\n' "$*" >&2
  exit "$GC_EXIT_PARTIAL"
}

gc_is_tty_stderr() {
  [[ -t 2 ]]
}

# Resolve option: explicit CLI > env > config file > default
resolve_option() {
  local cli="$1" env_val="$2" config_val="$3" default_val="$4"
  if [[ -n "$cli" ]]; then
    printf '%s' "$cli"
  elif [[ -n "$env_val" ]]; then
    printf '%s' "$env_val"
  elif [[ -n "$config_val" ]]; then
    printf '%s' "$config_val"
  else
    printf '%s' "$default_val"
  fi
}

# Load data/<owner>/catalog.config into associative array GC_CONFIG
declare -gA GC_CONFIG=()

load_owner_config() {
  local owner="$1"
  local repo_root="${REPO_ROOT:-}"
  local config_file

  GC_CONFIG=()

  [[ -n "$owner" ]] || return 0
  [[ -n "$repo_root" ]] || return 0

  config_file="$repo_root/data/$owner/catalog.config"
  [[ -f "$config_file" ]] || return 0

  local line key value
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -n "$line" ]] || continue
    [[ "$line" == *=* ]] || continue
    key="${line%%=*}"
    value="${line#*=}"
    key="${key%"${key##*[![:space:]]}"}"
    value="${value#"${value%%[![:space:]]*}"}"
    GC_CONFIG["$key"]="$value"
  done < "$config_file"
}

gc_config_get() {
  local key="$1"
  printf '%s' "${GC_CONFIG[$key]:-}"
}

# Version helpers for doctor
gc_bash_version_ok() {
  (( BASH_VERSINFO[0] >= 5 ))
}

gc_bash_version_string() {
  printf '%s.%s' "${BASH_VERSINFO[0]}" "${BASH_VERSINFO[1]}"
}

gc_jq_version_ok() {
  local ver
  ver="$(jq --version 2>/dev/null | sed -n 's/^jq-\{0,1\}//p')"
  [[ -n "$ver" ]] || return 1
  awk -v v="$ver" 'BEGIN {
    split(v, a, ".");
    if (a[1] > 1) exit 0;
    if (a[1] < 1) exit 1;
    if (a[2] >= 7) exit 0;
    exit 1;
  }'
}

gc_jq_version_string() {
  jq --version 2>/dev/null | sed 's/^jq-//'
}

gc_git_version_string() {
  git --version 2>/dev/null | awk '{print $3}'
}
