#!/usr/bin/env bash
# tests/test_doctor.sh - doctor preflight checks
set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
DOCTOR="$REPO_ROOT/scripts/github-catalog-doctor.sh"

test_doctor_runs() {
  local out
  out="$("$DOCTOR" 2>&1)"
  grep -q 'github-catalog doctor' <<< "$out" || return 1
  grep -q 'bash' <<< "$out" || return 1
  grep -q 'jq' <<< "$out" || return 1
  grep -q 'git' <<< "$out" || return 1
}

test_doctor_inventory_summary() {
  local work owner out
  work="$(mktemp -d)"
  owner="_doc_test"
  mkdir -p "$work/data/$owner"
  cat > "$work/data/$owner/user-repositories.jsonl" <<'JSONL'
{"schema_version":"1.2.0","record_type":"user_repository","report_id":"2026-06-17T12:00:00Z","generated_at":"2026-06-17T12:00:00Z","owner":"_doc_test","repo_slug":"demo","repo_url":"https://github.com/_doc_test/demo","visibility":"public","default_branch":"main","status":"active"}
JSONL
  REPO_ROOT="$work" out="$("$DOCTOR" "$owner" 2>&1)"
  grep -q 'inventory present (1 repos' <<< "$out" || return 1
  rm -rf "$work"
}
