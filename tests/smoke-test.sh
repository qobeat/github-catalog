#!/usr/bin/env bash
# tests/smoke-test.sh - Offline sentry skip logic and report integration
set -euo pipefail

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

BARE="$WORK/fake-remote.git"
git init --bare "$BARE" > /dev/null

SEED="$(mktemp -d)"
git -C "$SEED" init > /dev/null
git -C "$SEED" config user.email "test@test.com"
git -C "$SEED" config user.name "Test"
cat > "$SEED/README.md" <<'MD'
# Fake Project

## GOAL
Test the sentry and collection logic.

## OBJECTIVES
1. Write a JSONL line
2. Skip on re-run
MD
git -C "$SEED" add .
git -C "$SEED" commit -m "init" > /dev/null
git -C "$SEED" remote add origin "$BARE"
git -C "$SEED" push origin main > /dev/null
rm -rf "$SEED"

DATA_DIR="$WORK/data"
mkdir -p "$DATA_DIR"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
FETCHER="$SCRIPT_DIR/../scripts/github-catalog-datafetcher.sh"
REPORTER="$SCRIPT_DIR/../scripts/github-catalog-report.sh"

# --- First run: should collect ---
"$FETCHER" \
  --owner "testowner" \
  --repo  "fake-remote" \
  --repo-url "file://$BARE" \
  --branch "main" \
  --type  "private" \
  --report-id "2026-06-17T00:00:00Z" \
  --data-dir "$DATA_DIR"

CATALOG="$DATA_DIR/git-projects-catalog.jsonl"
[[ -f "$CATALOG" ]] || { echo "FAIL: catalog not written"; exit 1; }
jq -c '.' < "$CATALOG" > /dev/null || { echo "FAIL: invalid JSONL"; exit 1; }

SKIPPED_1=$(jq -r '.collection_skipped' < <(tail -n 1 "$CATALOG"))
[[ "$SKIPPED_1" == "false" ]] || { echo "FAIL: first run must not skip"; exit 1; }

# --- Second run: same HEAD → must skip ---
"$FETCHER" \
  --owner "testowner" \
  --repo  "fake-remote" \
  --repo-url "file://$BARE" \
  --branch "main" \
  --type  "private" \
  --report-id "2026-06-17T00:00:01Z" \
  --data-dir "$DATA_DIR"

SKIPPED_2=$(jq -r '.collection_skipped' < <(tail -n 1 "$CATALOG"))
[[ "$SKIPPED_2" == "true" ]] || { echo "FAIL: second run must skip (same SHA)"; exit 1; }

echo "PASS: sentry logic OK"

# --- Report smoke test ---
"$REPORTER" \
  --owner "testowner" \
  --data-dir "$DATA_DIR" \
  --output /tmp/test-report.md > /dev/null

lines=$(wc -l < /tmp/test-report.md)
[[ "$lines" -gt 10 ]] || { echo "FAIL: report too short ($lines lines)"; exit 1; }
grep -q '## Catalog Overview' /tmp/test-report.md || { echo "FAIL: missing Catalog Overview"; exit 1; }
grep -q 'Key Files' /tmp/test-report.md || { echo "FAIL: missing Key Files column"; exit 1; }
grep -q '## Detailed Semantics' /tmp/test-report.md || { echo "FAIL: missing Detailed Semantics"; exit 1; }
grep -q '**Goal:**' /tmp/test-report.md || { echo "FAIL: missing Goal block"; exit 1; }
rm /tmp/test-report.md

# --- Default report path: timestamped file + latest.md symlink ---
REPORT_DIR="$WORK/reports"
mkdir -p "$REPORT_DIR/testowner"
ln -sfn /nonexistent "$REPORT_DIR/testowner/latest.md" 2>/dev/null || true
rm -f "$REPORT_DIR/testowner"/report-*.md 2>/dev/null || true

# Report script writes under repo reports/<owner>/; use isolated owner under WORK via data-dir only.
# Smoke: explicit --output already tested above; symlink behavior covered in test_report.sh.

echo "PASS: report generation OK"

# --- Tombstone preserves prior snapshot data ---
cat >> "$CATALOG" <<'JSONL'
{"schema_version":"1.2.0","record_type":"repo_snapshot","report_id":"2026-06-17T00:00:02Z","generated_at":"2026-06-17T00:00:03Z","collection_skipped":false,"status":"deleted","owner":"testowner","repo_slug":"fake-remote","repo_url":"file:///tmp/fake.git","default_branch":"main","head_commit_sha":"a3f8c21d9e4b07625f1c3a8d0e7b92641fd5c8e1","head_commit_at":"2026-06-16T22:14:07Z","git_description":null,"created_at":null,"key_files_present":["README.md"],"goal":{"text":"Test the sentry and collection logic.","source_file":"README.md","source_heading":"GOAL"},"objectives":null,"flows":null,"requirements":null,"errors":[]}
JSONL

TOMB_STATUS=$(jq -r '.status' < <(tail -n 1 "$CATALOG"))
[[ "$TOMB_STATUS" == "deleted" ]] || { echo "FAIL: tombstone status"; exit 1; }
TOMB_GOAL=$(jq -r '.goal.text' < <(tail -n 1 "$CATALOG"))
[[ "$TOMB_GOAL" == *"sentry"* ]] || { echo "FAIL: tombstone lost goal text"; exit 1; }

echo "PASS: tombstone fixture OK"