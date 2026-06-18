#!/usr/bin/env bash
# Unit tests for JSONL record shape (mirrors docs/github-catalog.schema.json)

validate_repo_snapshot() {
  local line="$1"
  jq -e '
    .record_type == "repo_snapshot"
    and (.schema_version | test("^[0-9]+\\.[0-9]+\\.[0-9]+$"))
    and (.report_id | test("^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}Z$"))
    and (.generated_at | test("^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}Z$"))
    and (.collection_skipped | type == "boolean")
    and (.owner | length > 0)
    and (.repo_slug | length > 0)
    and (.repo_url | type == "string")
    and (.default_branch | length > 0)
    and (.head_commit_sha | test("^[0-9a-f]{40}$"))
    and (.key_files_present | type == "array")
    and (.errors | type == "array")
  ' <<< "$line" >/dev/null
}

validate_commit() {
  local line="$1"
  jq -e '
    .record_type == "commit"
    and (.sha | test("^[0-9a-f]{40}$"))
    and (.short_sha | length == 7)
    and (.message | type == "string")
    and (.files_changed | type == "number")
  ' <<< "$line" >/dev/null
}

validate_run() {
  local line="$1"
  jq -e '
    .record_type == "run"
    and (.repos_glob | type == "string")
    and (.visibility_filter | IN("private", "public", "all"))
    and (.repos_total | type == "number")
    and (.repos_completed | type == "number")
    and (.failures | type == "number")
    and (.parallel | type == "number" and . >= 1)
  ' <<< "$line" >/dev/null
}

FIXTURE_SNAPSHOT='{
  "schema_version": "1.0.0",
  "record_type": "repo_snapshot",
  "report_id": "2026-06-17T12:00:00Z",
  "generated_at": "2026-06-17T12:00:04Z",
  "collection_skipped": false,
  "owner": "testowner",
  "repo_slug": "fake-remote",
  "repo_url": "file:///tmp/fake.git",
  "default_branch": "main",
  "head_commit_sha": "a3f8c21d9e4b07625f1c3a8d0e7b92641fd5c8e1",
  "head_commit_at": "2026-06-16T22:14:07Z",
  "git_description": null,
  "created_at": "2023-11-01T09:30:00Z",
  "key_files_present": ["README.md"],
  "goal": {"text": "A goal", "source_file": "README.md", "source_heading": "GOAL"},
  "objectives": null,
  "flows": null,
  "requirements": null,
  "errors": []
}'

FIXTURE_COMMIT='{
  "schema_version": "1.0.0",
  "record_type": "commit",
  "report_id": "2026-06-17T12:00:00Z",
  "generated_at": "2026-06-17T12:00:06Z",
  "owner": "testowner",
  "repo_slug": "fake-remote",
  "repo_url": "file:///tmp/fake.git",
  "default_branch": "main",
  "sha": "a3f8c21d9e4b07625f1c3a8d0e7b92641fd5c8e1",
  "short_sha": "a3f8c21",
  "committed_at": "2026-06-16T22:14:07Z",
  "author_name": "Test",
  "author_email": "test@test.com",
  "message": "init",
  "files_changed": 1
}'

FIXTURE_RUN='{
  "schema_version": "1.0.0",
  "record_type": "run",
  "report_id": "2026-06-17T12:00:00Z",
  "generated_at": "2026-06-17T12:00:10Z",
  "owner": "testowner",
  "repos_glob": "*",
  "visibility_filter": "private",
  "repos_total": 1,
  "repos_completed": 1,
  "failures": 0,
  "parallel": 4
}'

test_schema_repo_snapshot_valid() {
  validate_repo_snapshot "$FIXTURE_SNAPSHOT"
}

test_schema_commit_valid() {
  validate_commit "$FIXTURE_COMMIT"
}

test_schema_run_valid() {
  validate_run "$FIXTURE_RUN"
}

test_schema_repo_snapshot_rejects_bad_sha() {
  local bad
  bad=$(jq -c '.head_commit_sha = "not-a-sha"' <<< "$FIXTURE_SNAPSHOT")
  if validate_repo_snapshot "$bad"; then
    return 1
  fi
}

test_schema_file_parses() {
  jq -e '.' "$REPO_ROOT/docs/github-catalog.schema.json" >/dev/null
}
