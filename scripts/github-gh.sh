#!/usr/bin/env bash
# scripts/github-gh.sh - Interface for GitHub commands missing in standard git
set -euo pipefail

usage() {
  cat <<'EOF'
github-gh.sh - GitHub API interaction layer

Commands:
  list-repos      Fetch repository list for a user using gh and output to JSONL

Required options for list-repos:
  --owner NAME              Git host owner
  --type private|public|all Visibility filter
  --report-id ID            Run ID to bind records to
  --data-dir DIR            Directory to append user-repositories.jsonl
  --limit N                 Max repos to query from GitHub

EOF
}

log_error() { printf 'ERROR: %s\n' "$*" >&2; }
fail() { log_error "$*"; exit 1; }

CMD="${1:-}"
[[ -n "$CMD" ]] || { usage; exit 1; }
shift

if ! command -v gh >/dev/null 2>&1; then
  fail "GitHub CLI ('gh') is required but not installed. This command cannot run."
fi

OWNER="" VISIBILITY="" REPORT_ID="" DATA_DIR="" LIMIT="1000"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --owner)     OWNER="${2:?}"; shift 2 ;;
    --type)      VISIBILITY="${2:?}"; shift 2 ;;
    --report-id) REPORT_ID="${2:?}"; shift 2 ;;
    --data-dir)  DATA_DIR="${2:?}"; shift 2 ;;
    --limit)     LIMIT="${2:?}"; shift 2 ;;
    -h|--help)   usage; exit 0 ;;
    *)           fail "unknown option: $1" ;;
  esac
done

if [[ "$CMD" == "list-repos" ]]; then
  [[ -n "$OWNER" ]] || fail "--owner is required"
  [[ -n "$DATA_DIR" ]] || fail "--data-dir is required"
  [[ -n "$REPORT_ID" ]] || fail "--report-id is required"
  
  mkdir -p "$DATA_DIR"
  OUT_FILE="$DATA_DIR/user-repositories.jsonl"
  
  # Prepare gh arguments
  GH_ARGS=( "$OWNER" "--limit" "$LIMIT" "--json" "name,url,visibility,defaultBranchRef" )
  if [[ "$VISIBILITY" != "all" && -n "$VISIBILITY" ]]; then
    GH_ARGS+=( "--visibility" "$VISIBILITY" )
  fi

  # Call gh and format output to schema-compliant JSONL via jq
  # shellcheck disable=SC2016
  gh repo list "${GH_ARGS[@]}" | jq -c \
    --arg sv "1.0.0" \
    --arg rid "$REPORT_ID" \
    --arg gat "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg own "$OWNER" \
    '.[] | {
      schema_version: $sv,
      record_type: "user_repository",
      report_id: $rid,
      generated_at: $gat,
      owner: $own,
      repo_slug: .name,
      repo_url: .url,
      visibility: (.visibility | ascii_downcase),
      default_branch: (.defaultBranchRef.name // "main")
    }' >> "$OUT_FILE"
    
  echo "Successfully refreshed $OUT_FILE"
else
  fail "Unknown command: $CMD"
fi