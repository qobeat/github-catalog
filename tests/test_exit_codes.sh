#!/usr/bin/env bash
# tests/test_exit_codes.sh - ADR-003 exit code contract
set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CLI="$REPO_ROOT/github-catalog"
# shellcheck source=scripts/github-catalog-lib.sh
source "$REPO_ROOT/scripts/github-catalog-lib.sh"

test_exit_usage_no_args() {
  local ec=0
  "$CLI" 2>/dev/null || ec=$?
  assert_eq "$GC_EXIT_USAGE" "$ec"
}

test_exit_usage_unknown_command() {
  local ec=0
  "$CLI" not-a-command 2>/dev/null || ec=$?
  assert_eq "$GC_EXIT_USAGE" "$ec"
}

test_exit_usage_report_missing_owner() {
  local ec=0
  "$CLI" report 2>/dev/null || ec=$?
  assert_eq "$GC_EXIT_USAGE" "$ec"
}

test_exit_precond_report_no_catalog() {
  local ec=0 work owner
  work="$(mktemp -d)"
  owner="_exit_nocat"
  HOME="$work" "$CLI" report "$owner" 2>/dev/null || ec=$?
  assert_eq "$GC_EXIT_PRECOND" "$ec"
  rm -rf "$work"
}

test_exit_precond_sync_no_owner() {
  local ec=0
  "$CLI" sync 2>/dev/null || ec=$?
  assert_eq "$GC_EXIT_USAGE" "$ec"
}
