#!/usr/bin/env bash
# tests/test_dry_run.sh - sync --dry-run produces no catalog writes
set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
FETCHER="$REPO_ROOT/scripts/github-catalog-datafetcher.sh"
ORCH="$REPO_ROOT/scripts/github-catalog-orchestrator.sh"

test_fetcher_dry_run_no_write() {
  local work bare seed catalog line
  work="$(mktemp -d)"
  bare="$work/fake.git"
  git init --bare "$bare" > /dev/null
  seed="$(mktemp -d)"
  git -C "$seed" init -b main > /dev/null
  git -C "$seed" config user.email "t@t.com"
  git -C "$seed" config user.name "T"
  echo hi > "$seed/README.md"
  git -C "$seed" add . && git -C "$seed" commit -m init > /dev/null
  git -C "$seed" remote add origin "$bare" && git -C "$seed" push -u origin main > /dev/null
  rm -rf "$seed"

  DATA_DIR="$work/data"
  mkdir -p "$DATA_DIR"
  catalog="$DATA_DIR/git-projects-catalog.jsonl"
  : > "$catalog"

  line="$("$FETCHER" \
    --owner testowner --repo fake --repo-url "file://$bare" \
    --branch main --type all --dry-run --data-dir "$DATA_DIR")"
  assert_match $'fake\tcollect\t' "$line"
  assert_eq "0" "$(wc -l < "$catalog" | tr -d ' ')"
  rm -rf "$work"
}

test_fetcher_dry_run_skip() {
  local work bare seed
  work="$(mktemp -d)"
  bare="$work/fake.git"
  git init --bare "$bare" > /dev/null
  seed="$(mktemp -d)"
  git -C "$seed" init -b main > /dev/null
  git -C "$seed" config user.email "t@t.com"
  git -C "$seed" config user.name "T"
  echo hi > "$seed/README.md"
  git -C "$seed" add . && git -C "$seed" commit -m init > /dev/null
  git -C "$seed" remote add origin "$bare" && git -C "$seed" push -u origin main > /dev/null
  rm -rf "$seed"

  DATA_DIR="$work/data"
  mkdir -p "$DATA_DIR"
  "$REPO_ROOT/scripts/github-catalog-datafetcher.sh" \
    --owner testowner --repo fake --repo-url "file://$bare" \
    --branch main --type all --report-id r1 --data-dir "$DATA_DIR" > /dev/null

  line="$("$FETCHER" \
    --owner testowner --repo fake --repo-url "file://$bare" \
    --branch main --type all --dry-run --data-dir "$DATA_DIR")"
  assert_match $'fake\tskip\t' "$line"
  rm -rf "$work"
}

test_orchestrator_dry_run_no_writes() {
  local work bare seed out owner
  work="$(mktemp -d)"
  owner="testowner"
  bare="$work/fake.git"
  git init --bare "$bare" > /dev/null
  seed="$(mktemp -d)"
  git -C "$seed" init -b main > /dev/null
  git -C "$seed" config user.email "t@t.com"
  git -C "$seed" config user.name "T"
  echo hi > "$seed/README.md"
  git -C "$seed" add . && git -C "$seed" commit -m init > /dev/null
  git -C "$seed" remote add origin "$bare" && git -C "$seed" push -u origin main > /dev/null
  rm -rf "$seed"

  mkdir -p "$work/data/$owner"
  cat > "$work/data/$owner/user-repositories.jsonl" <<JSONL
{"schema_version":"1.2.0","record_type":"user_repository","report_id":"2026-01-01T00:00:00Z","generated_at":"2026-01-01T00:00:00Z","owner":"$owner","repo_slug":"fake","repo_url":"file://$bare","visibility":"public","default_branch":"main","status":"active"}
JSONL

  out="$("$ORCH" \
    --owner "$owner" \
    --repos fake \
    --type all \
    --data-dir "$work/data/$owner" \
    --log-dir "$work/logs" \
    --dry-run \
    --quiet 2>/dev/null)"

  grep -q $'fake\tcollect\t' <<< "$out" || grep -q $'fake\tskip\t' <<< "$out" || return 1
  [[ ! -f "$work/data/$owner/git-projects-catalog.jsonl" ]] || [[ ! -s "$work/data/$owner/git-projects-catalog.jsonl" ]] || return 1
  rm -rf "$work"
}
