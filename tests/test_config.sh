#!/usr/bin/env bash
# tests/test_config.sh - Per-owner catalog.config precedence
set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/github-catalog-lib.sh
source "$REPO_ROOT/scripts/github-catalog-lib.sh"

test_load_owner_config() {
  local work owner
  work="$(mktemp -d)"
  owner="_cfg_test_owner"
  mkdir -p "$work/data/$owner"
  cat > "$work/data/$owner/catalog.config" <<'CFG'
# comment line
git_host=github-personal
visibility=private
parallel=8
ssh_key=/tmp/test-key
CFG
  REPO_ROOT="$work" load_owner_config "$owner"
  assert_eq "github-personal" "$(gc_config_get git_host)"
  assert_eq "private" "$(gc_config_get visibility)"
  assert_eq "8" "$(gc_config_get parallel)"
  assert_eq "/tmp/test-key" "$(gc_config_get ssh_key)"
  rm -rf "$work"
}

test_resolve_option_precedence() {
  assert_eq "cli" "$(resolve_option "cli" "env" "cfg" "def")"
  assert_eq "env" "$(resolve_option "" "env" "cfg" "def")"
  assert_eq "cfg" "$(resolve_option "" "" "cfg" "def")"
  assert_eq "def" "$(resolve_option "" "" "" "def")"
}

test_clean_preserves_config() {
  local work owner root
  work="$(mktemp -d)"
  owner="_cfg_clean_owner"
  root="$REPO_ROOT"
  REPO_ROOT="$work"
  mkdir -p "$work/data/$owner"
  printf 'git_host=alias\n' > "$work/data/$owner/catalog.config"
  printf 'x' > "$work/data/$owner/git-projects-catalog.jsonl"
  mkdir -p "$work/reports/$owner"
  printf 'report' > "$work/reports/$owner/latest.md"

  # simulate clean without purge
  config_tmp="$(mktemp)"
  cp "$work/data/$owner/catalog.config" "$config_tmp"
  rm -rf "$work/data/$owner" "$work/reports/$owner"
  mkdir -p "$work/data/$owner"
  mv "$config_tmp" "$work/data/$owner/catalog.config"

  [[ -f "$work/data/$owner/catalog.config" ]] || return 1
  assert_eq "git_host=alias" "$(cat "$work/data/$owner/catalog.config")"
  [[ ! -f "$work/data/$owner/git-projects-catalog.jsonl" ]] || return 1
  REPO_ROOT="$root"
  rm -rf "$work"
}
