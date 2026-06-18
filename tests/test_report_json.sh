#!/usr/bin/env bash
# tests/test_report_json.sh - report --format json
set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
REPORTER="$REPO_ROOT/scripts/github-catalog-report.sh"

test_report_json_structure() {
  local work owner out
  work="$(mktemp -d)"
  owner="_json_test"
  mkdir -p "$work/data/$owner"
  cat > "$work/data/$owner/git-projects-catalog.jsonl" <<'JSONL'
{"schema_version":"1.2.0","record_type":"repo_snapshot","report_id":"2026-06-17T12:00:00Z","generated_at":"2026-06-17T12:00:01Z","collection_skipped":false,"status":"active","owner":"_json_test","repo_slug":"demo","repo_url":"https://github.com/_json_test/demo","default_branch":"main","head_commit_sha":"a3f8c21d9e4b07625f1c3a8d0e7b92641fd5c8e1","head_commit_at":"2026-06-16T22:14:07Z","git_description":null,"created_at":null,"key_files_present":["README.md"],"goal":{"text":"Demo goal","source_file":"README.md","source_heading":"GOAL"},"objectives":null,"flows":null,"requirements":null,"errors":[]}
{"schema_version":"1.0.0","record_type":"run","report_id":"2026-06-17T12:00:00Z","generated_at":"2026-06-17T12:00:02Z","owner":"_json_test","repos_glob":"*","visibility_filter":"all","repos_total":1,"repos_completed":1,"failures":0,"parallel":4}
JSONL

  out="$("$REPORTER" --owner "$owner" --data-dir "$work/data/$owner" --format json)"
  assert_eq "_json_test" "$(jq -r '.owner' <<< "$out")"
  assert_eq "1" "$(jq -r '.overview.repos_cataloged' <<< "$out")"
  assert_eq "demo" "$(jq -r '.repositories[0].repo_slug' <<< "$out")"
  assert_eq "Demo goal" "$(jq -r '.repositories[0].goal_excerpt' <<< "$out")"
  assert_eq "2026-06-17T12:00:00Z" "$(jq -r '.overview.last_run.report_id' <<< "$out")"
  rm -rf "$work"
}

test_report_md_still_works() {
  local work owner out
  work="$(mktemp -d)"
  owner="_json_md_test"
  mkdir -p "$work/data/$owner" "$work/reports/$owner"
  cat > "$work/data/$owner/git-projects-catalog.jsonl" <<'JSONL'
{"schema_version":"1.2.0","record_type":"repo_snapshot","report_id":"2026-06-17T12:00:00Z","generated_at":"2026-06-17T12:00:01Z","collection_skipped":false,"status":"active","owner":"_json_md_test","repo_slug":"demo","repo_url":"https://github.com/_json_md_test/demo","default_branch":"main","head_commit_sha":"a3f8c21d9e4b07625f1c3a8d0e7b92641fd5c8e1","head_commit_at":"2026-06-16T22:14:07Z","git_description":null,"created_at":null,"key_files_present":[],"goal":null,"objectives":null,"flows":null,"requirements":null,"errors":[]}
JSONL
  out="$("$REPORTER" --owner "$owner" --data-dir "$work/data/$owner" --output "$work/out.md" 2>&1)"
  grep -q '## Catalog Overview' "$work/out.md" || return 1
  rm -rf "$work"
}
