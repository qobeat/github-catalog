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
rm /tmp/test-report.md

echo "PASS: report generation OK"