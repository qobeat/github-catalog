#!/usr/bin/env bash
# tests/test_report.sh - Report generator section and error-message tests

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPORTER="$SCRIPT_DIR/../scripts/github-catalog-report.sh"

test_report_has_summary_sections() {
  local work catalog out
  work="$(mktemp -d)"
  catalog="$work/git-projects-catalog.jsonl"
  out="$work/report.md"

  cat > "$catalog" <<'JSONL'
{"schema_version":"1.0.0","record_type":"repo_snapshot","report_id":"2026-06-17T12:00:00Z","generated_at":"2026-06-17T12:00:01Z","collection_skipped":false,"owner":"testowner","repo_slug":"demo","repo_url":"https://github.com/testowner/demo","default_branch":"main","head_commit_sha":"a3f8c21d9e4b07625f1c3a8d0e7b92641fd5c8e1","head_commit_at":"2026-06-16T22:14:07Z","git_description":null,"created_at":"2023-11-01T09:30:00Z","key_files_present":["README.md"],"goal":{"text":"Demo goal text","source_file":"README.md","source_heading":"GOAL"},"objectives":null,"flows":null,"requirements":null,"errors":[]}
JSONL

  "$REPORTER" --owner testowner --data-dir "$work" --output "$out" >/dev/null

  grep -q '## Catalog Overview' "$out" || return 1
  grep -q '## Repository Summary' "$out" || return 1
  grep -q 'Key Files' "$out" || return 1
  grep -q '## Detailed Semantics' "$out" || return 1
  grep -q '**Goal:**' "$out" || return 1

  rm -rf "$work"
}

test_report_default_creates_timestamp_and_symlink() {
  local work report_dir first_count second_count repo_root
  work="$(mktemp -d)"
  repo_root="$(cd -- "$SCRIPT_DIR/.." && pwd)"
  report_dir="$repo_root/reports/_ts_test_owner"
  rm -rf "$report_dir"

  mkdir -p "$work/data/_ts_test_owner"
  cat > "$work/data/_ts_test_owner/git-projects-catalog.jsonl" <<'JSONL'
{"schema_version":"1.2.0","record_type":"repo_snapshot","report_id":"2026-06-17T12:00:00Z","generated_at":"2026-06-17T12:00:01Z","collection_skipped":false,"status":"active","owner":"_ts_test_owner","repo_slug":"demo","repo_url":"https://github.com/_ts_test_owner/demo","default_branch":"main","head_commit_sha":"a3f8c21d9e4b07625f1c3a8d0e7b92641fd5c8e1","head_commit_at":"2026-06-16T22:14:07Z","git_description":null,"created_at":null,"key_files_present":[],"goal":null,"objectives":null,"flows":null,"requirements":null,"errors":[]}
JSONL

  "$REPORTER" --owner _ts_test_owner --data-dir "$work/data/_ts_test_owner" >/dev/null

  [[ -L "$report_dir/latest.md" ]] || { rm -rf "$work" "$report_dir"; return 1; }
  first_count=$(find "$report_dir" -maxdepth 1 -name 'report-*.md' | wc -l)
  [[ "$first_count" -ge 1 ]] || { rm -rf "$work" "$report_dir"; return 1; }

  "$REPORTER" --owner _ts_test_owner --data-dir "$work/data/_ts_test_owner" >/dev/null

  second_count=$(find "$report_dir" -maxdepth 1 -name 'report-*.md' | wc -l)
  [[ "$second_count" -eq "$first_count" ]] || { rm -rf "$work" "$report_dir"; return 1; }

  rm -rf "$work" "$report_dir"
}

test_report_creates_new_when_catalog_changes() {
  local work report_dir repo_root catalog latest
  work="$(mktemp -d)"
  repo_root="$(cd -- "$SCRIPT_DIR/.." && pwd)"
  report_dir="$repo_root/reports/_ts_test_owner"
  catalog="$work/data/_ts_test_owner/git-projects-catalog.jsonl"
  rm -rf "$report_dir"

  mkdir -p "$work/data/_ts_test_owner"
  cat > "$catalog" <<'JSONL'
{"schema_version":"1.2.0","record_type":"repo_snapshot","report_id":"2026-06-17T12:00:00Z","generated_at":"2026-06-17T12:00:01Z","collection_skipped":false,"status":"active","owner":"_ts_test_owner","repo_slug":"demo","repo_url":"https://github.com/_ts_test_owner/demo","default_branch":"main","head_commit_sha":"a3f8c21d9e4b07625f1c3a8d0e7b92641fd5c8e1","head_commit_at":"2026-06-16T22:14:07Z","git_description":null,"created_at":null,"key_files_present":[],"goal":null,"objectives":null,"flows":null,"requirements":null,"errors":[]}
JSONL

  "$REPORTER" --owner _ts_test_owner --data-dir "$work/data/_ts_test_owner" >/dev/null
  latest="$report_dir/$(readlink "$report_dir/latest.md")"
  grep -q 'demo' "$latest" || { rm -rf "$work" "$report_dir"; return 1; }
  grep -q 'other' "$latest" && { rm -rf "$work" "$report_dir"; return 1; }

  cat >> "$catalog" <<'JSONL'
{"schema_version":"1.2.0","record_type":"repo_snapshot","report_id":"2026-06-17T13:00:00Z","generated_at":"2026-06-17T13:00:01Z","collection_skipped":false,"status":"active","owner":"_ts_test_owner","repo_slug":"other","repo_url":"https://github.com/_ts_test_owner/other","default_branch":"main","head_commit_sha":"b4f9d32e0f5c18736g2d4b9e1f8c03752ge6d9f2","head_commit_at":"2026-06-17T10:00:00Z","git_description":null,"created_at":null,"key_files_present":[],"goal":null,"objectives":null,"flows":null,"requirements":null,"errors":[]}
JSONL

  "$REPORTER" --owner _ts_test_owner --data-dir "$work/data/_ts_test_owner" >/dev/null
  latest="$report_dir/$(readlink "$report_dir/latest.md")"
  grep -q 'other' "$latest" || { rm -rf "$work" "$report_dir"; return 1; }

  rm -rf "$work" "$report_dir"
}

test_report_reuses_existing_when_latest_target_missing() {
  local work report_dir repo_root catalog latest_name kept_name
  work="$(mktemp -d)"
  repo_root="$(cd -- "$SCRIPT_DIR/.." && pwd)"
  report_dir="$repo_root/reports/_ts_test_owner"
  catalog="$work/data/_ts_test_owner/git-projects-catalog.jsonl"
  rm -rf "$report_dir"

  mkdir -p "$work/data/_ts_test_owner"
  cat > "$catalog" <<'JSONL'
{"schema_version":"1.2.0","record_type":"repo_snapshot","report_id":"2026-06-17T12:00:00Z","generated_at":"2026-06-17T12:00:01Z","collection_skipped":false,"status":"active","owner":"_ts_test_owner","repo_slug":"demo","repo_url":"https://github.com/_ts_test_owner/demo","default_branch":"main","head_commit_sha":"a3f8c21d9e4b07625f1c3a8d0e7b92641fd5c8e1","head_commit_at":"2026-06-16T22:14:07Z","git_description":null,"created_at":null,"key_files_present":[],"goal":null,"objectives":null,"flows":null,"requirements":null,"errors":[]}
JSONL

  "$REPORTER" --owner _ts_test_owner --data-dir "$work/data/_ts_test_owner" >/dev/null
  latest_name="$(readlink "$report_dir/latest.md")"
  kept_name="report-kept-copy.md"
  cp "$report_dir/$latest_name" "$report_dir/$kept_name"
  rm -f "$report_dir/$latest_name"

  "$REPORTER" --owner _ts_test_owner --data-dir "$work/data/_ts_test_owner" >/dev/null
  [[ "$(find "$report_dir" -maxdepth 1 -name 'report-*.md' | wc -l)" -eq 1 ]] || { rm -rf "$work" "$report_dir"; return 1; }
  [[ "$(readlink "$report_dir/latest.md")" == "$kept_name" ]] || { rm -rf "$work" "$report_dir"; return 1; }

  rm -rf "$work" "$report_dir"
}

test_report_marks_deleted_repos() {
  local work catalog out
  work="$(mktemp -d)"
  catalog="$work/git-projects-catalog.jsonl"
  out="$work/report.md"

  cat > "$catalog" <<'JSONL'
{"schema_version":"1.2.0","record_type":"repo_snapshot","report_id":"2026-06-17T12:00:00Z","generated_at":"2026-06-17T12:00:01Z","collection_skipped":false,"status":"deleted","owner":"testowner","repo_slug":"gone-repo","repo_url":"https://github.com/testowner/gone-repo","default_branch":"main","head_commit_sha":"a3f8c21d9e4b07625f1c3a8d0e7b92641fd5c8e1","head_commit_at":"2026-06-16T22:14:07Z","git_description":null,"created_at":null,"key_files_present":[],"goal":{"text":"Preserved goal","source_file":"README.md","source_heading":"GOAL"},"objectives":null,"flows":null,"requirements":null,"errors":[]}
JSONL

  "$REPORTER" --owner testowner --data-dir "$work" --output "$out" >/dev/null

  grep -qF '[deleted]' "$out" || return 1
  grep -q 'Repositories deleted:**' "$out" || return 1
  grep -q 'Preserved goal' "$out" || return 1

  rm -rf "$work"
}

test_report_includes_flows() {
  local work catalog out
  work="$(mktemp -d)"
  catalog="$work/git-projects-catalog.jsonl"
  out="$work/report.md"

  cat > "$catalog" <<'JSONL'
{"schema_version":"1.0.0","record_type":"repo_snapshot","report_id":"2026-06-17T12:00:00Z","generated_at":"2026-06-17T12:00:01Z","collection_skipped":false,"owner":"testowner","repo_slug":"flow-demo","repo_url":"https://github.com/testowner/flow-demo","default_branch":"main","head_commit_sha":"a3f8c21d9e4b07625f1c3a8d0e7b92641fd5c8e1","head_commit_at":"2026-06-16T22:14:07Z","git_description":null,"created_at":null,"key_files_present":[],"goal":null,"objectives":null,"flows":{"text":"install → configure → run","source_file":"README.md","source_heading":"Typical Workflows"},"requirements":null,"errors":[]}
JSONL

  "$REPORTER" --owner testowner --data-dir "$work" --output "$out" >/dev/null

  grep -q '**Flows:**' "$out" || return 1
  grep -q 'Typical Workflows' "$out" || return 1

  rm -rf "$work"
}

test_report_missing_catalog_shows_sync_help() {
  local work err
  work="$(mktemp -d)"
  err="$(mktemp)"

  if "$REPORTER" --owner nobody --data-dir "$work" --output "$work/out.md" 2>"$err"; then
    rm -rf "$work" "$err"
    return 1
  fi

  grep -q './github-catalog sync nobody' "$err" || { rm -rf "$work" "$err"; return 1; }
  grep -q 'git-projects-catalog.jsonl' "$err" || { rm -rf "$work" "$err"; return 1; }
  grep -q 'no local data for owner' "$err" || { rm -rf "$work" "$err"; return 1; }

  rm -rf "$work" "$err"
}

test_report_inventory_hint_when_cached() {
  local work err inventory
  work="$(mktemp -d)"
  err="$(mktemp)"
  inventory="$work/user-repositories.jsonl"

  echo '{"record_type":"user_repository","owner":"cached","repo_slug":"x"}' > "$inventory"

  if "$REPORTER" --owner cached --data-dir "$work" --output "$work/out.md" 2>"$err"; then
    rm -rf "$work" "$err"
    return 1
  fi

  grep -q 'inventory exists at' "$err" || { rm -rf "$work" "$err"; return 1; }
  grep -q 'no --refresh needed' "$err" || { rm -rf "$work" "$err"; return 1; }

  rm -rf "$work" "$err"
}
