#!/usr/bin/env bash
# tests/test_status.sh - status command digest
set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
STATUS="$REPO_ROOT/scripts/github-catalog-status.sh"

test_status_owner_list() {
  local work out
  work="$(mktemp -d)"
  mkdir -p "$work/data/owner_a" "$work/data/owner_b"
  printf '{"record_type":"repo_snapshot","repo_slug":"x","generated_at":"2026-01-01T00:00:00Z","status":"active","errors":[]}\n' \
    > "$work/data/owner_a/git-projects-catalog.jsonl"
  printf '{"record_type":"repo_snapshot","repo_slug":"y","generated_at":"2026-01-01T00:00:00Z","status":"active","errors":[]}\n' \
    > "$work/data/owner_b/git-projects-catalog.jsonl"

  REPO_ROOT="$work" out="$(find "$work/data" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | sort)"
  # status script uses REPO_ROOT from its own SCRIPT_DIR parent - patch via env
  out="$(
    REPO_ROOT="$work" "$STATUS" --format json
  )"
  assert_eq "2" "$(jq '.owners | length' <<< "$out")"
  rm -rf "$work"
}

test_status_owner_digest() {
  local work owner out
  work="$(mktemp -d)"
  owner="_st_test"
  mkdir -p "$work/data/$owner"
  cat > "$work/data/$owner/git-projects-catalog.jsonl" <<'JSONL'
{"schema_version":"1.2.0","record_type":"repo_snapshot","report_id":"r1","generated_at":"2026-06-17T12:00:01Z","collection_skipped":false,"status":"active","owner":"_st_test","repo_slug":"ok","repo_url":"https://github.com/_st_test/ok","default_branch":"main","head_commit_sha":"abc","head_commit_at":"2026-06-17T10:00:00Z","key_files_present":[],"goal":null,"objectives":null,"flows":null,"requirements":null,"errors":[]}
{"schema_version":"1.2.0","record_type":"repo_snapshot","report_id":"r1","generated_at":"2026-06-17T12:00:02Z","collection_skipped":false,"status":"active","owner":"_st_test","repo_slug":"bad","repo_url":"https://github.com/_st_test/bad","default_branch":"main","head_commit_sha":"def","head_commit_at":"2026-06-17T10:00:00Z","key_files_present":[],"goal":null,"objectives":null,"flows":null,"requirements":null,"errors":["unreachable"]}
{"schema_version":"1.0.0","record_type":"run","report_id":"2026-06-17T12:00:00Z","generated_at":"2026-06-17T12:00:02Z","owner":"_st_test","repos_glob":"*","visibility_filter":"all","repos_total":2,"repos_completed":2,"failures":1,"parallel":4}
JSONL

  out="$(
    REPO_ROOT="$work" "$STATUS" "$owner"
  )"
  grep -q 'github-catalog status: _st_test' <<< "$out" || return 1
  grep -q '2 cataloged' <<< "$out" || return 1
  grep -q 'bad' <<< "$out" || return 1
  rm -rf "$work"
}
