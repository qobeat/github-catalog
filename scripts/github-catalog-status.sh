#!/usr/bin/env bash
# scripts/github-catalog-status.sh - Fast catalog overview (no report file write)
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd -- "$SCRIPT_DIR/.." && pwd)}"
# shellcheck source=scripts/github-catalog-lib.sh
source "$SCRIPT_DIR/github-catalog-lib.sh"

usage() {
  cat <<'EOF'
github-catalog-status.sh - Compact catalog digest

Usage:
  scripts/github-catalog-status.sh [owner] [--format text|json]

Options:
  --format text|json    Output format (default: text)
  --data-dir DIR      Override data directory for owner
  -h, --help          Show this help
EOF
}

list_owners_json() {
  local data_root="$REPO_ROOT/data"
  jq -nc --argjson owners "$(find_owners_json_array)" '{owners: $owners}'
}

find_owners_json_array() {
  local data_root="$REPO_ROOT/data"
  local owners=()
  local d catalog owner count last_run active deleted errors

  [[ -d "$data_root" ]] || { printf '[]'; return; }

  for d in "$data_root"/*; do
    [[ -d "$d" ]] || continue
    catalog="$d/git-projects-catalog.jsonl"
    [[ -f "$catalog" ]] || continue
    owner="$(basename "$d")"

    read -r count active deleted errors last_run < <(
      jq -rn '
        [inputs] as $all |
        ($all | map(select(.record_type == "repo_snapshot"))
          | group_by(.repo_slug) | map(sort_by(.generated_at) | last)) as $repos |
        ($all | map(select(.record_type == "run")) | sort_by(.generated_at) | last) as $run |
        [
          ($repos | length),
          ($repos | map(select((.status // "active") == "active")) | length),
          ($repos | map(select((.status // "active") == "deleted")) | length),
          ($repos | map(select(((.errors // []) | length) > 0 and (.status // "active") != "deleted")) | length),
          (if $run == null then "" else $run.report_id end)
        ] | @tsv
      ' "$catalog" 2>/dev/null || printf '0\t0\t0\t0\t'
    )

    owners+=("$(jq -nc \
      --arg owner "$owner" \
      --argjson repos "${count:-0}" \
      --argjson active "${active:-0}" \
      --argjson deleted "${deleted:-0}" \
      --argjson errors "${errors:-0}" \
      --arg last_run "${last_run:-}" \
      '{owner: $owner, repos_cataloged: $repos, repos_active: $active, repos_deleted: $deleted, repos_with_errors: $errors, last_sync_run: (if $last_run == "" then null else $last_run end)}')")
  done

  if ((${#owners[@]} == 0)); then
    printf '[]'
  else
    printf '%s\n' "${owners[@]}" | jq -s '.'
  fi
}

print_owners_text() {
  local json
  json="$(list_owners_json)"
  local count
  count="$(jq '.owners | length' <<< "$json")"
  if (( count == 0 )); then
    echo "No cataloged owners found under data/"
    return
  fi
  echo "Cataloged owners:"
  jq -r '.owners[] |
    "  \(.owner): \(.repos_cataloged) repos (\(.repos_active) active, \(.repos_deleted) deleted)" +
    (if .last_sync_run then ", last sync \(.last_sync_run)" else "" end) +
    (if .repos_with_errors > 0 then ", \(.repos_with_errors) with errors" else "" end)
  ' <<< "$json"
}

print_owner_text() {
  local owner="$1" data_dir="$2" catalog commits json

  catalog="$data_dir/git-projects-catalog.jsonl"
  commits="$data_dir/git-projects-commits.jsonl"

  if [[ ! -f "$catalog" ]]; then
    gc_exit_precond "no catalog for owner '$owner' at $catalog"
  fi

  json="$(build_owner_status_json "$owner" "$catalog" "$commits")"

  echo "github-catalog status: $owner"
  jq -r '
    "  Repositories: \(.overview.repos_cataloged) cataloged (\(.overview.repos_deleted) deleted)",
    (if .overview.last_run != null then
      "  Last sync: \(.overview.last_run.report_id) — \(.overview.last_run.repos_completed)/\(.overview.last_run.repos_total) completed, \(.overview.last_run.failures) failures"
    else "  Last sync: none" end),
    "  Skipped on last snapshot: \(.overview.repos_skipped_last_snapshot)",
    (if (.errors | length) > 0 then
      "  Repos with errors: \(.errors | map(.repo_slug) | join(", "))"
    else "  Repos with errors: none" end)
  ' <<< "$json"
}

build_owner_status_json() {
  local owner="$1" catalog="$2" commits="$3"
  local date
  date="$(date -u +"%Y-%m-%d %H:%M UTC")"
  {
    cat "$catalog"
    if [[ -f "$commits" ]] && [[ -s "$commits" ]]; then
      cat "$commits"
    fi
  } | jq -rn \
    --arg owner "$owner" \
    --arg date "$date" \
    -f "$SCRIPT_DIR/report-data.jq"
}

OWNER=""
FORMAT="text"
DATA_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --format)  FORMAT="${2:?}"; shift 2 ;;
    --data-dir) DATA_DIR="${2:?}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    --*) gc_exit_usage "unknown option $1" ;;
    *)
      [[ -z "$OWNER" ]] || gc_exit_usage "unexpected argument: $1"
      OWNER="$1"
      shift
      ;;
  esac
done

[[ "$FORMAT" == "text" || "$FORMAT" == "json" ]] || gc_exit_usage "--format must be text or json"

if [[ -z "$OWNER" ]]; then
  if [[ "$FORMAT" == "json" ]]; then
    list_owners_json
  else
    print_owners_text
  fi
  exit 0
fi

if [[ -z "$DATA_DIR" ]]; then
  DATA_DIR="$REPO_ROOT/data/$OWNER"
fi

if [[ "$FORMAT" == "json" ]]; then
  catalog="$DATA_DIR/git-projects-catalog.jsonl"
  commits="$DATA_DIR/git-projects-commits.jsonl"
  [[ -f "$catalog" ]] || gc_exit_precond "no catalog for owner '$OWNER'"
  build_owner_status_json "$OWNER" "$catalog" "$commits"
else
  print_owner_text "$OWNER" "$DATA_DIR"
fi
