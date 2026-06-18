#!/usr/bin/env bash
# tests/smoke-test.sh — offline integration tests (ADR steps 14–15)
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
FETCHER="$REPO_ROOT/scripts/github-catalog-datafetcher.sh"
REPORTER="$REPO_ROOT/scripts/github-catalog-report.sh"

[[ -x "$FETCHER" ]]  || { echo "FAIL: fetcher not executable: $FETCHER"; exit 1; }
[[ -x "$REPORTER" ]] || { echo "FAIL: reporter not executable: $REPORTER"; exit 1; }

WORK="$(mktemp -d)"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

# --- Create local bare git repo ---
BARE="$WORK/fake-remote.git"
git init --bare "$BARE" >/dev/null

SEED="$WORK/seed"
mkdir -p "$SEED"
git -C "$SEED" init -q
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
git -C "$SEED" commit -qm "init"
git -C "$SEED" branch -M main
git -C "$SEED" remote add origin "$BARE"
git -C "$SEED" push -q origin main

DATA_DIR="$WORK/data"
mkdir -p "$DATA_DIR"
LOG_FILE="$WORK/test.log"
CATALOG="$DATA_DIR/git-projects-catalog.jsonl"

# --- Step 14: first run collects ---
"$FETCHER" \
  --owner "testowner" \
  --repo  "fake-remote" \
  --repo-url "file://$BARE" \
  --branch "main" \
  --type  "private" \
  --report-id "2026-06-17T00:00:00Z" \
  --data-dir "$DATA_DIR" \
  --log-file "$LOG_FILE"

[[ -f "$CATALOG" ]] || { echo "FAIL: catalog not written"; exit 1; }
jq -c '.' < "$CATALOG" >/dev/null || { echo "FAIL: invalid JSONL after first run"; exit 1; }

SKIPPED_1=$(jq -r '.collection_skipped' < <(tail -1 "$CATALOG"))
[[ "$SKIPPED_1" == "false" ]] || { echo "FAIL: first run must not skip (got $SKIPPED_1)"; exit 1; }

GOAL_TEXT=$(jq -r '.goal.text' < <(tail -1 "$CATALOG"))
[[ -n "$GOAL_TEXT" && "$GOAL_TEXT" != "null" ]] || { echo "FAIL: goal.text empty on first run"; exit 1; }

# --- Step 14: second run skips ---
"$FETCHER" \
  --owner "testowner" \
  --repo  "fake-remote" \
  --repo-url "file://$BARE" \
  --branch "main" \
  --type  "private" \
  --report-id "2026-06-17T00:00:01Z" \
  --data-dir "$DATA_DIR" \
  --log-file "$LOG_FILE"

SKIPPED_2=$(jq -r '.collection_skipped' < <(tail -1 "$CATALOG"))
[[ "$SKIPPED_2" == "true" ]] || { echo "FAIL: second run must skip (got $SKIPPED_2)"; exit 1; }

jq -c '.' < "$CATALOG" >/dev/null || { echo "FAIL: invalid JSONL after second run"; exit 1; }

echo "PASS: sentry logic OK"

# --- Step 15: report smoke ---
REPORT_OUT="$WORK/report.md"
COMMITS="$DATA_DIR/git-projects-commits.jsonl"
touch "$COMMITS"

"$REPORTER" \
  --catalog "$CATALOG" \
  --commits "$COMMITS" \
  --output "$REPORT_OUT"

LINE_COUNT=$(wc -l < "$REPORT_OUT" | tr -d ' ')
(( LINE_COUNT > 10 )) || { echo "FAIL: report too short ($LINE_COUNT lines)"; exit 1; }
grep -q "## Summary" "$REPORT_OUT" || { echo "FAIL: report missing Summary section"; exit 1; }
grep -q "## Commit Activity" "$REPORT_OUT" || { echo "FAIL: report missing Commit Activity section"; exit 1; }
grep -q "## Repository Details" "$REPORT_OUT" || { echo "FAIL: report missing Repository Details section"; exit 1; }
grep -q "fake-remote" "$REPORT_OUT" || { echo "FAIL: report missing repo slug"; exit 1; }

echo "PASS: report generation OK"
