#!/usr/bin/env bash
# scripts/github-gh.sh - Interface for GitHub commands missing in standard git
set -euo pipefail

usage() {
  cat <<'EOF'
github-gh.sh - GitHub API interaction layer

Commands:
  list-repos      Fetch repository list for a user using gh and output to JSONL
  get-repo        Fetch one repository using gh repo view and output to JSONL

Required options for list-repos / get-repo:
  --owner NAME              Git host owner
  --type private|public|all Visibility filter
  --report-id ID            Run ID to bind records to
  --data-dir DIR            Directory to append user-repositories.jsonl

Options for list-repos:
  --limit N                 Max repos to query from GitHub (default: 1000)
  --tombstones-file FILE    Write one tombstoned repo_slug per line (list-repos only)

Required for get-repo:
  --repo SLUG               Repository short name (without owner/)

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

OWNER="" REPO_SLUG="" VISIBILITY="" REPORT_ID="" DATA_DIR="" LIMIT="1000" TOMBSTONES_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --owner)     OWNER="${2:?}"; shift 2 ;;
    --repo)      REPO_SLUG="${2:?}"; shift 2 ;;
    --type)      VISIBILITY="${2:?}"; shift 2 ;;
    --report-id) REPORT_ID="${2:?}"; shift 2 ;;
    --data-dir)  DATA_DIR="${2:?}"; shift 2 ;;
    --limit)     LIMIT="${2:?}"; shift 2 ;;
    --tombstones-file) TOMBSTONES_FILE="${2:?}"; shift 2 ;;
    -h|--help)   usage; exit 0 ;;
    *)           fail "unknown option: $1" ;;
  esac
done

format_repo_record() {
  local status="${1:-active}"
  jq -c \
    --arg sv "1.2.0" \
    --arg rid "$REPORT_ID" \
    --arg gat "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg own "$OWNER" \
    --arg st "$status" \
    '{
      schema_version: $sv,
      record_type: "user_repository",
      report_id: $rid,
      generated_at: $gat,
      owner: $own,
      repo_slug: .name,
      repo_url: .url,
      visibility: (.visibility | ascii_downcase),
      default_branch: (.defaultBranchRef.name // "main"),
      status: $st
    }'
}

format_tombstone_record() {
  jq -c \
    --arg sv "1.2.0" \
    --arg rid "$REPORT_ID" \
    --arg gat "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg own "$OWNER" \
    '{
      schema_version: $sv,
      record_type: "user_repository",
      report_id: $rid,
      generated_at: $gat,
      owner: $own,
      repo_slug: .repo_slug,
      repo_url: .repo_url,
      visibility: .visibility,
      default_branch: .default_branch,
      status: "deleted"
    }'
}

append_deletion_tombstones() {
  local out_file="$1"
  local fresh_slugs_file="$2"
  [[ -f "$out_file" ]] || return 0

  local fresh_slugs_json tombstones
  fresh_slugs_json=$(jq -Rsc 'split("\n") | map(select(length > 0))' "$fresh_slugs_file")

  tombstones=$(jq -rnc \
    --arg vis "$VISIBILITY" \
    --argjson fresh "$fresh_slugs_json" \
    '[inputs
      | select(.record_type == "user_repository")
      | select($vis == "all" or (.visibility | ascii_downcase) == $vis)
    ]
    | group_by(.repo_slug)
    | map(sort_by(.generated_at) | last)
    | map(select((.status // "active") == "active"))
    | map(select(.repo_slug as $s | ($fresh | index($s)) == null))
    | .[]' \
    "$out_file" 2>/dev/null || true)

  if [[ -z "$tombstones" ]]; then
    : > "${TOMBSTONES_FILE:-/dev/null}"
    return 0
  fi

  while IFS= read -r prior; do
    [[ -n "$prior" ]] || continue
    printf '%s\n' "$prior" | format_tombstone_record >> "$out_file"
    if [[ -n "$TOMBSTONES_FILE" ]]; then
      printf '%s\n' "$(jq -r '.repo_slug' <<< "$prior")" >> "$TOMBSTONES_FILE"
    fi
  done <<< "$tombstones"
}

repo_matches_visibility() {
  local repo_vis="$1"
  [[ "$VISIBILITY" == "all" || "$VISIBILITY" == "$repo_vis" ]]
}

if [[ "$CMD" == "list-repos" ]]; then
  [[ -n "$OWNER" ]] || fail "--owner is required"
  [[ -n "$DATA_DIR" ]] || fail "--data-dir is required"
  [[ -n "$REPORT_ID" ]] || fail "--report-id is required"

  mkdir -p "$DATA_DIR"
  OUT_FILE="$DATA_DIR/user-repositories.jsonl"

  GH_ARGS=( "$OWNER" "--limit" "$LIMIT" "--json" "name,url,visibility,defaultBranchRef" )
  if [[ "$VISIBILITY" != "all" && -n "$VISIBILITY" ]]; then
    GH_ARGS+=( "--visibility" "$VISIBILITY" )
  fi

  FRESH_SLUGS_FILE="$(mktemp)"
  FRESH_JSON_FILE="$(mktemp)"
  trap 'rm -f "$FRESH_SLUGS_FILE" "$FRESH_JSON_FILE"' EXIT

  gh repo list "${GH_ARGS[@]}" > "$FRESH_JSON_FILE"

  jq -c '.[]' "$FRESH_JSON_FILE" | format_repo_record active >> "$OUT_FILE"
  jq -r '.[].name' "$FRESH_JSON_FILE" > "$FRESH_SLUGS_FILE"

  if [[ -n "$TOMBSTONES_FILE" ]]; then
    : > "$TOMBSTONES_FILE"
  fi
  append_deletion_tombstones "$OUT_FILE" "$FRESH_SLUGS_FILE"

  echo "Successfully refreshed $OUT_FILE"
elif [[ "$CMD" == "get-repo" ]]; then
  [[ -n "$OWNER" ]] || fail "--owner is required"
  [[ -n "$REPO_SLUG" ]] || fail "--repo is required"
  [[ -n "$DATA_DIR" ]] || fail "--data-dir is required"
  [[ -n "$REPORT_ID" ]] || fail "--report-id is required"

  mkdir -p "$DATA_DIR"
  OUT_FILE="$DATA_DIR/user-repositories.jsonl"

  repo_json=$(gh repo view "$OWNER/$REPO_SLUG" \
    --json name,url,visibility,defaultBranchRef 2>/dev/null) \
    || fail "repository not found or not accessible: $OWNER/$REPO_SLUG"

  repo_vis=$(printf '%s' "$repo_json" | jq -r '.visibility | ascii_downcase')
  if ! repo_matches_visibility "$repo_vis"; then
    fail "repository $OWNER/$REPO_SLUG is $repo_vis, does not match --type $VISIBILITY"
  fi

  printf '%s\n' "$repo_json" | format_repo_record active >> "$OUT_FILE"

  echo "Successfully refreshed $OUT_FILE"
else
  fail "Unknown command: $CMD"
fi
