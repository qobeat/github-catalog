#!/usr/bin/env bash
# github-catalog-datafetcher.sh — single-repo sentry + collection (skeleton)
set -euo pipefail

usage() {
  cat <<'EOF'
github-catalog-datafetcher.sh - collect one repository into JSONL

Required:
  --owner NAME              Git host owner or organization
  --repo SLUG               Repository short name (no owner prefix)
  --type private|public|all Visibility filter (recorded in run metadata)
  --report-id ID            UTC run id shared with orchestrator (ISO 8601)

Options:
  --repo-url URL            Full clone URL (SSH, HTTPS, or file://)
  --branch NAME             Default branch (default: main)
  --data-dir DIR            JSONL output directory (default: data/)
  --log-file PATH           Structured run log file (default: logs/github-catalog-YYYY-MM-DD.log)
  -h, --help                Show this help

EOF
}

log() {
  local level="$1"
  shift
  printf '%s [%s] %s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$level" "$*" >> "$LOG_FILE"
}

log_cmd()   { log CMD   "$*"; }
log_info()  { log INFO  "$*"; }
log_error() { log ERROR "$*"; }

fail() {
  log_error "$*"
  exit 1
}

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

OWNER=""
REPO_SLUG=""
VISIBILITY=""
REPORT_ID=""
REPO_URL=""
BRANCH="main"
DATA_DIR="$REPO_ROOT/data"
LOG_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --owner|--user) OWNER="${2:?}"; shift 2 ;;
    --repo)         REPO_SLUG="${2:?}"; shift 2 ;;
    --type)         VISIBILITY="${2:?}"; shift 2 ;;
    --report-id)    REPORT_ID="${2:?}"; shift 2 ;;
    --repo-url)     REPO_URL="${2:?}"; shift 2 ;;
    --branch)       BRANCH="${2:?}"; shift 2 ;;
    --data-dir)     DATA_DIR="${2:?}"; shift 2 ;;
    --log-file)     LOG_FILE="${2:?}"; shift 2 ;;
    -h|--help)      usage; exit 0 ;;
    *)              fail "unknown option: $1" ;;
  esac
done

[[ -n "$OWNER" ]]      || fail "--owner is required"
[[ -n "$REPO_SLUG" ]]  || fail "--repo is required"
[[ -n "$VISIBILITY" ]] || fail "--type is required"
[[ -n "$REPORT_ID" ]]  || fail "--report-id is required"
[[ "$VISIBILITY" =~ ^(private|public|all)$ ]] || fail "--type must be private, public, or all"

if [[ -z "$LOG_FILE" ]]; then
  LOG_FILE="$REPO_ROOT/logs/github-catalog-$(date -u +%Y-%m-%d).log"
fi

mkdir -p "$DATA_DIR" "$(dirname -- "$LOG_FILE")"

CATALOG_JSONL="$DATA_DIR/git-projects-catalog.jsonl"
COMMITS_JSONL="$DATA_DIR/git-projects-commits.jsonl"

if [[ -z "$REPO_URL" ]]; then
  REPO_URL="git@github.com:${OWNER}/${REPO_SLUG}.git"
fi

log_info "START repo=$REPO_SLUG owner=$OWNER branch=$BRANCH report_id=$REPORT_ID"

# Step 4+: sentry logic, bare clone, extraction, JSONL append
