#!/usr/bin/env bash
# github-catalog-orchestrator.sh — parallel dispatch + progress + run summary
set -euo pipefail

usage() {
  cat <<'EOF'
github-catalog-orchestrator.sh - run catalog datafetchers in parallel

Required:
  --owner, --user NAME_OR_URL   Git host owner (URL forms like https://github.com/qobeat accepted)
  --repos GLOB                  Repository glob, e.g. '*' or 'ados-*'
  --type private|public|all     Visibility filter (recorded in run summary)

Options:
  --git-host HOST               SSH config Host alias for git URLs (default: github.com)
  --ssh-key PATH                Private key for git operations (optional)
  --refresh-repo-list           Call github-gh.sh to fetch the latest repo list from GitHub
  --parallel N                  Max concurrent workers (default: 4)
  --limit N                     Cap matched repos (0 = no limit)
  --data-dir DIR                Base JSONL directory (default: data/<user-name>)
  --log-dir DIR                 Log file directory (default: logs/)
  --report-id ID                UTC run id (default: current timestamp)
  --fetcher PATH                Datafetcher script
  -h, --help                    Show this help

EOF
}

log() {
  local level="$1"
  shift
  printf '%s [%s] %s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$level" "$*" >> "$LOG_FILE"
}

log_info()  { log INFO  "$*"; }
log_error() { log ERROR "$*"; }

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  [[ -n "${LOG_FILE:-}" ]] && log_error "$*"
  exit 1
}

progress_bar() {
  local current=$1 total=$2 label=$3
  local width=24
  local filled empty bar
  filled=$(( total > 0 ? current * width / total : 0 ))
  empty=$(( width - filled ))
  bar="$(printf '%0.s#' $(seq 1 "$filled"))$(printf '%0.s.' $(seq 1 "$empty"))"
  printf '\r\033[K\033[1m[%s]\033[0m %d/%d  %s' \
    "$bar" "$current" "$total" "$label" >&2
}

normalize_owner() {
  local o="$1"
  o="${o#https://}"
  o="${o#http://}"
  o="${o#www.}"
  o="${o#github.com/}"
  o="${o%/}"
  printf '%s' "$o"
}

match_glob() {
  local name="$1" pattern="$2"
  # shellcheck disable=SC2053
  [[ "$name" == $pattern ]]
}

glob_has_wildcards() {
  [[ "$1" == *[\*\?\[]* ]]
}

build_git_repo_url() {
  local owner="$1" slug="$2"
  local host="${GIT_HOST:-github.com}"
  printf 'git@%s:%s/%s.git' "$host" "$owner" "$slug"
}

setup_git_ssh() {
  [[ -z "$SSH_KEY" ]] && return 0
  export GIT_SSH_COMMAND="ssh -i ${SSH_KEY} -o IdentitiesOnly=yes -o BatchMode=yes"
}

resolve_repo_url() {
  local slug="$1"
  if [[ -n "$GIT_HOST" ]]; then
    build_git_repo_url "$OWNER" "$slug"
  elif [[ -n "${REPO_URLS[$slug]+x}" ]]; then
    printf '%s' "${REPO_URLS[$slug]}"
  else
    build_git_repo_url "$OWNER" "$slug"
  fi
}

detect_default_branch() {
  local url="$1"
  local symref
  symref=$(git ls-remote --symref "$url" HEAD 2>/dev/null \
    | awk '/^ref:/ { sub(/^ref: refs\/heads\//, "", $2); print $2; exit }')
  [[ -n "$symref" ]] && printf '%s' "$symref" || printf 'main'
}

needs_gh_inventory() {
  (( REFRESH_REPO_LIST == 1 )) && return 0
  glob_has_wildcards "$REPOS_GLOB" && return 0
  [[ -z "$GIT_HOST" ]] && return 0
  return 1
}

try_literal_repo_probe() {
  local url branch
  [[ -n "$REPOS_GLOB" ]] || return 1
  glob_has_wildcards "$REPOS_GLOB" && return 1

  setup_git_ssh
  url="$(build_git_repo_url "$OWNER" "$REPOS_GLOB")"
  git ls-remote "$url" HEAD >/dev/null 2>&1 || return 1

  branch="$(detect_default_branch "$url")"
  REPOS=("$REPOS_GLOB")
  REPO_URLS["$REPOS_GLOB"]="$url"
  REPO_BRANCHES["$REPOS_GLOB"]="$branch"
  log_info "LITERAL_PROBE ok repo=$REPOS_GLOB url=$url branch=$branch"
  return 0
}

fail_no_repos_matched() {
  local check_url msg vis_suffix=""
  local inventory_count=0

  if [[ -f "$REPO_LIST_FILE" ]]; then
    inventory_count=$(jq -rn --arg vis "$VISIBILITY" '
      [inputs | select(.record_type == "user_repository")]
      | group_by(.repo_slug)
      | map(sort_by(.generated_at) | last)
      | map(select($vis == "all" or (.visibility | ascii_downcase) == $vis))
      | map(select((.status // "active") == "active"))
      | length
    ' "$REPO_LIST_FILE" 2>/dev/null || echo 0)
  fi

  if [[ "$VISIBILITY" != "all" ]]; then
    vis_suffix="visibility filter: $VISIBILITY"
  fi

  if glob_has_wildcards "$REPOS_GLOB"; then
    check_url="prefetched inventory ($inventory_count repos, gh limit 1000)"
    msg="no repositories matched glob '$REPOS_GLOB' in $check_url for owner '$OWNER'"
    [[ -n "$vis_suffix" ]] && msg="$msg ($vis_suffix)"
    msg="$msg; try --refresh after 'gh auth login' for the correct account"
  else
    check_url="$(build_git_repo_url "$OWNER" "$REPOS_GLOB")"
    msg="no repository reachable at $check_url"
    [[ -n "$vis_suffix" ]] && msg="$msg ($vis_suffix)"
    if [[ -z "$GIT_HOST" ]]; then
      msg="$msg; if you use SSH host aliases, pass --git-host"
    fi
  fi

  fail "$msg"
}

append_run_record() {
  local record
  record=$(jq -nc \
    --arg sv "1.0.0" \
    --arg rid "$REPORT_ID" \
    --arg gat "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg own "$OWNER" \
    --arg glob "$REPOS_GLOB" \
    --arg vis "$VISIBILITY" \
    --argjson total "$total" \
    --argjson completed "$completed" \
    --argjson failures "$failures" \
    --argjson parallel "$PARALLEL" \
    '{
      schema_version: $sv,
      record_type: "run",
      report_id: $rid,
      generated_at: $gat,
      owner: $own,
      repos_glob: $glob,
      visibility_filter: $vis,
      repos_total: $total,
      repos_completed: $completed,
      failures: $failures,
      parallel: $parallel
    }')
  local lock_file="$DATA_DIR/.catalog.lock"
  (
    flock -x 200
    printf '%s\n' "$record" >> "$CATALOG_JSONL"
  ) 200>"$lock_file"
}

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

OWNER=""
REPOS_GLOB=""
VISIBILITY=""
PARALLEL="4"
LIMIT="0"
DATA_DIR="$REPO_ROOT/data"
LOG_DIR="$REPO_ROOT/logs"
REPORT_ID="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
FETCHER="$SCRIPT_DIR/github-catalog-datafetcher.sh"
GH_HELPER="$SCRIPT_DIR/github-gh.sh"
REFRESH_REPO_LIST=0
GIT_HOST="${GITHUB_CATALOG_GIT_HOST:-}"
SSH_KEY="${GITHUB_CATALOG_SSH_KEY:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --user|--owner) OWNER="${2:?}"; shift 2 ;;
    --repos)        REPOS_GLOB="${2:?}"; shift 2 ;;
    --type)         VISIBILITY="${2:?}"; shift 2 ;;
    --git-host)     GIT_HOST="${2:?}"; shift 2 ;;
    --ssh-key)      SSH_KEY="${2:?}"; shift 2 ;;
    --parallel)     PARALLEL="${2:?}"; shift 2 ;;
    --limit)        LIMIT="${2:?}"; shift 2 ;;
    --data-dir)     DATA_DIR="${2:?}"; shift 2 ;;
    --log-dir)      LOG_DIR="${2:?}"; shift 2 ;;
    --report-id)    REPORT_ID="${2:?}"; shift 2 ;;
    --fetcher)      FETCHER="${2:?}"; shift 2 ;;
    --refresh-repo-list) REFRESH_REPO_LIST=1; shift 1 ;;
    -h|--help)      usage; exit 0 ;;
    *)              fail "unknown option: $1" ;;
  esac
done

[[ -n "$OWNER" ]]           || fail "--owner is required"
[[ -n "$REPOS_GLOB" ]]      || fail "--repos is required"
[[ -n "$VISIBILITY" ]]      || fail "--type is required"
[[ "$VISIBILITY" =~ ^(private|public|all)$ ]] || fail "--type must be private, public, or all"
[[ -x "$FETCHER" ]]         || fail "fetcher not executable: $FETCHER"

if ! [[ "$PARALLEL" =~ ^[0-9]+$ ]] || ! (( PARALLEL >= 1 )); then
  fail "--parallel must be >= 1"
fi
if ! [[ "$LIMIT" =~ ^[0-9]+$ ]]; then
  fail "--limit must be >= 0"
fi

OWNER="$(normalize_owner "$OWNER")"

# Establish target user directory
if [[ "$DATA_DIR" == "$REPO_ROOT/data" ]]; then
  DATA_DIR="$DATA_DIR/$OWNER"
fi

mkdir -p "$DATA_DIR" "$LOG_DIR"
LOG_FILE="$LOG_DIR/github-catalog-$(date -u +%Y-%m-%d).log"
CATALOG_JSONL="$DATA_DIR/git-projects-catalog.jsonl"
REPO_LIST_FILE="$DATA_DIR/user-repositories.jsonl"

setup_git_ssh

# Fetch list from GitHub when inventory is required
if needs_gh_inventory; then
  if [[ ! -f "$REPO_LIST_FILE" ]] || (( REFRESH_REPO_LIST == 1 )); then
    log_info "Refreshing repository list via github-gh.sh..."
    TOMBSTONES_FILE="$(mktemp)"
    "$GH_HELPER" list-repos \
      --owner "$OWNER" \
      --type "$VISIBILITY" \
      --report-id "$REPORT_ID" \
      --data-dir "$DATA_DIR" \
      --limit 1000 \
      --tombstones-file "$TOMBSTONES_FILE"

    if [[ -s "$TOMBSTONES_FILE" ]]; then
      while IFS= read -r deleted_slug; do
        [[ -n "$deleted_slug" ]] || continue
        log_info "CATALOG_TOMBSTONE repo=$deleted_slug"
        "$FETCHER" \
          --owner "$OWNER" \
          --repo "$deleted_slug" \
          --type "$VISIBILITY" \
          --report-id "$REPORT_ID" \
          --data-dir "$DATA_DIR" \
          --log-file "$LOG_FILE" \
          --tombstone 2>>"$LOG_FILE" || true
      done < "$TOMBSTONES_FILE"
    fi
    rm -f "$TOMBSTONES_FILE"
  fi
  [[ -f "$REPO_LIST_FILE" ]] || fail "Repo list file not found and could not be generated: $REPO_LIST_FILE"
elif [[ ! -f "$REPO_LIST_FILE" ]]; then
  log_info "Skipping gh inventory (literal glob + --git-host, no --refresh)"
fi

declare -a REPOS=()
declare -A REPO_URLS=()
declare -A REPO_BRANCHES=()

if [[ -f "$REPO_LIST_FILE" ]]; then
  count=0

  # Parse the user_repository JSONL file, deduplicating by slug to get the latest state
  while IFS=$'\t' read -r slug url branch; do
    [[ -n "$slug" ]] || continue
    match_glob "$slug" "$REPOS_GLOB" || continue

    REPOS+=("$slug")
    [[ -n "$url" ]]    && REPO_URLS["$slug"]="$url"
    [[ -n "$branch" ]] && REPO_BRANCHES["$slug"]="$branch"

    count=$((count + 1))
    if (( LIMIT > 0 && count >= LIMIT )); then
      break
    fi
  done < <(jq -rn --arg vis "$VISIBILITY" '
    [inputs | select(.record_type == "user_repository")]
    | group_by(.repo_slug)
    | map(sort_by(.generated_at) | last)
    | .[]
    | select($vis == "all" or (.visibility | ascii_downcase) == $vis)
    | select((.status // "active") == "active")
    | [ .repo_slug, (.repo_url // ""), (.default_branch // "") ] | @tsv
  ' "$REPO_LIST_FILE")
fi

if ((${#REPOS[@]} == 0)); then
  try_literal_repo_probe || fail_no_repos_matched
fi

total=${#REPOS[@]}
running=0
completed=0
failures=0

log_info "RUN_START report_id=$REPORT_ID owner=$OWNER repos=$total parallel=$PARALLEL glob=$REPOS_GLOB type=$VISIBILITY"

for repo in "${REPOS[@]}"; do
  log_info "DISPATCH repo=$repo running=$running parallel=$PARALLEL"
  progress_bar "$completed" "$total" "dispatching → $repo"

  fetcher_args=(
    "$FETCHER"
    --owner "$OWNER"
    --repo "$repo"
    --type "$VISIBILITY"
    --report-id "$REPORT_ID"
    --data-dir "$DATA_DIR"
    --log-file "$LOG_FILE"
  )
  fetcher_args+=(--repo-url "$(resolve_repo_url "$repo")")
  [[ -n "${REPO_BRANCHES[$repo]+x}" ]] && fetcher_args+=(--branch "${REPO_BRANCHES[$repo]}")
  [[ -n "$SSH_KEY" ]] && fetcher_args+=(--ssh-key "$SSH_KEY")
  [[ -n "$GIT_HOST" ]] && fetcher_args+=(--git-host "$GIT_HOST")

  "${fetcher_args[@]}" 2>>"$LOG_FILE" &

  running=$((running + 1))
  sleep 1

  while (( running >= PARALLEL )); do
    if wait -n; then
      log_info "WORKER_OK slot_freed"
    else
      ec=$?
      failures=$((failures + 1))
      log_error "WORKER_FAIL exit=$ec"
    fi
    running=$((running - 1))
    completed=$((completed + 1))
    progress_bar "$completed" "$total" "running $running workers"
  done
done

while (( running > 0 )); do
  if wait -n; then
    log_info "DRAIN_OK"
  else
    ec=$?
    failures=$((failures + 1))
    log_error "DRAIN_FAIL exit=$ec"
  fi
  running=$((running - 1))
  completed=$((completed + 1))
  progress_bar "$completed" "$total" "draining ($running left)"
done

printf '\n' >&2

log_info "RUN_DONE report_id=$REPORT_ID completed=$completed failures=$failures"
append_run_record

if (( failures > 0 )); then
  printf 'FAILED: %d worker(s) failed. See %s\n' "$failures" "$LOG_FILE" >&2
  exit 1
fi