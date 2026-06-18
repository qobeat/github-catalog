#!/usr/bin/env bash
# github-catalog-refresh.sh — inventory-only refresh from GitHub (no catalog collection)
set -euo pipefail

usage() {
  cat <<'EOF'
github-catalog-refresh.sh - Refresh user-repositories.jsonl from GitHub

Usage:
  github-catalog-refresh.sh <owner> [--private|--public|--all]
  github-catalog-refresh.sh <owner>/<repo> [--private|--public|--all]

Arguments:
  <owner>              GitHub user or org (URL forms like https://github.com/owner accepted)
  <owner>/<repo>       Refresh a single repository entry

Options:
  --private            Fetch only private repositories (or require private for single repo)
  --public             Fetch only public repositories (or require public for single repo)
  --all                Fetch all visibilities (default)
  --limit N            Max repos to fetch for full owner refresh (default: 1000)
  --data-dir DIR       Override output directory (default: data/<owner>/)
  -h, --help           Show this help

Writes append-only records to data/<owner>/user-repositories.jsonl.
Requires authenticated gh for private repos; public repos work without auth.

EOF
}

log_error() { printf 'ERROR: %s\n' "$*" >&2; }
fail() { log_error "$*"; exit 1; }

normalize_owner() {
  local o="$1"
  o="${o#https://}"
  o="${o#http://}"
  o="${o#www.}"
  o="${o#github.com/}"
  o="${o%/}"
  printf '%s' "$o"
}

parse_target() {
  local raw="$1"
  local normalized

  normalized="$(normalize_owner "$raw")"
  [[ -n "$normalized" ]] || fail "owner name is required"

  if [[ "$normalized" == */* ]]; then
    OWNER="${normalized%%/*}"
    REPO_SLUG="${normalized#*/}"
    [[ -n "$OWNER" && -n "$REPO_SLUG" ]] || fail "invalid target '$raw'; expected <owner> or <owner>/<repo>"
  else
    OWNER="$normalized"
    REPO_SLUG=""
  fi
}

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
GH_HELPER="$SCRIPT_DIR/github-gh.sh"

TARGET=""
VISIBILITY="all"
LIMIT="1000"
DATA_DIR_OVERRIDE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --private) VISIBILITY="private"; shift ;;
    --public)  VISIBILITY="public"; shift ;;
    --all)     VISIBILITY="all"; shift ;;
    --limit)   LIMIT="${2:?--limit requires a value}"; shift 2 ;;
    --data-dir)
      DATA_DIR_OVERRIDE="${2:?--data-dir requires a value}"
      shift 2
      ;;
    -h|--help) usage; exit 0 ;;
    --target)
      TARGET="${2:?--target requires a value}"
      shift 2
      ;;
    --type)
      VISIBILITY="${2:?--type requires a value}"
      shift 2
      ;;
    -*)
      fail "unknown option: $1"
      ;;
    *)
      [[ -z "$TARGET" ]] || fail "unexpected argument: $1"
      TARGET="$1"
      shift
      ;;
  esac
done

[[ -n "$TARGET" ]] || { usage; exit 1; }
[[ "$VISIBILITY" =~ ^(private|public|all)$ ]] || fail "--type must be private, public, or all"

OWNER=""
REPO_SLUG=""
parse_target "$TARGET"

if [[ -n "$DATA_DIR_OVERRIDE" ]]; then
  DATA_DIR="$DATA_DIR_OVERRIDE"
else
  DATA_DIR="$REPO_ROOT/data/$OWNER"
fi
REPORT_ID="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
OUT_FILE="$DATA_DIR/user-repositories.jsonl"

mkdir -p "$DATA_DIR"

  if [[ -n "$REPO_SLUG" ]]; then
  "$GH_HELPER" get-repo \
    --owner "$OWNER" \
    --repo "$REPO_SLUG" \
    --type "$VISIBILITY" \
    --report-id "$REPORT_ID" \
    --data-dir "$DATA_DIR"
else
  TOMBSTONES_FILE="$(mktemp)"
  trap 'rm -f "$TOMBSTONES_FILE"' EXIT
  "$GH_HELPER" list-repos \
    --owner "$OWNER" \
    --type "$VISIBILITY" \
    --report-id "$REPORT_ID" \
    --data-dir "$DATA_DIR" \
    --limit "$LIMIT" \
    --tombstones-file "$TOMBSTONES_FILE"

  if [[ -s "$TOMBSTONES_FILE" ]]; then
  tombstone_count=$(wc -l < "$TOMBSTONES_FILE" | tr -d ' ')
  printf 'Marked %d repository(ies) as deleted in inventory\n' "$tombstone_count"
  fi
fi

count=0
if [[ -f "$OUT_FILE" ]]; then
  count=$(jq -rn --arg vis "$VISIBILITY" --arg rid "$REPORT_ID" '
    [inputs | select(.record_type == "user_repository" and .report_id == $rid)]
    | map(select($vis == "all" or (.visibility | ascii_downcase) == $vis))
    | length
  ' "$OUT_FILE" 2>/dev/null || echo 0)
fi

if [[ -n "$REPO_SLUG" ]]; then
  printf 'Refreshed 1 repository for %s/%s → %s (%d record)\n' \
    "$OWNER" "$REPO_SLUG" "$OUT_FILE" "$count"
else
  printf 'Refreshed repository list for %s → %s (%d repos)\n' \
    "$OWNER" "$OUT_FILE" "$count"
fi
