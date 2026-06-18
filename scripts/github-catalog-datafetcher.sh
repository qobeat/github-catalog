#!/usr/bin/env bash
# github-catalog-datafetcher.sh — single-repo sentry + collection
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
  --git-host HOST           SSH config Host alias (default: github.com)
  --ssh-key PATH            Private key for git operations (optional)
  --branch NAME             Default branch (default: main)
  --data-dir DIR            JSONL output directory (default: data/<owner>)
  --log-file PATH           Structured run log file
  --tombstone               Write deleted repo_snapshot from prior data (no git calls)
  --dry-run                 Sentry only: print planned action, no writes
  -h, --help                Show this help

EOF
}

log() {
  local level="$1"
  shift
  printf '%s [%s] %s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$level" "$*" >> "$LOG_FILE"
}

log_cmd()    { log CMD   "$*"; }
log_info()   { log INFO  "$*"; }
log_error()  { log ERROR "$*"; }
log_result() { log INFO  "RESULT cmd=$1 exit=$2 $3"; }

fail() {
  log_error "$*"
  exit 1
}

append_jsonl() {
  local file="$1"
  local line="$2"
  local lock_file="$DATA_DIR/.catalog.lock"
  (
    flock -x 200
    printf '%s\n' "$line" >> "$file"
  ) 200>"$lock_file"
}

append_catalog() {
  append_jsonl "$CATALOG_JSONL" "$1"
}

append_commit() {
  append_jsonl "$COMMITS_JSONL" "$1"
}

write_error_record() {
  local err_msg="${1:-unreachable}"
  local inv_status="active"
  local inventory_file="$DATA_DIR/user-repositories.jsonl"
  if [[ -f "$inventory_file" ]]; then
    inv_status=$(jq -rn --arg slug "$REPO_SLUG" \
      '[inputs | select(.record_type == "user_repository" and .repo_slug == $slug)]
       | sort_by(.generated_at) | last | .status // "active"' \
      "$inventory_file" 2>/dev/null || echo active)
  fi

  if [[ "$inv_status" == "deleted" ]]; then
    write_deleted_record
    return
  fi

  local record
  record=$(jq -nc \
    --arg sv "1.2.0" \
    --arg rid "$REPORT_ID" \
    --arg gat "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg own "$OWNER" \
    --arg slug "$REPO_SLUG" \
    --arg url "$REPO_URL" \
    --arg br "$BRANCH" \
    --arg err "$err_msg" \
    '{
      schema_version: $sv,
      record_type: "repo_snapshot",
      report_id: $rid,
      generated_at: $gat,
      collection_skipped: false,
      status: "active",
      owner: $own,
      repo_slug: $slug,
      repo_url: $url,
      default_branch: $br,
      head_commit_sha: "0000000000000000000000000000000000000000",
      head_commit_at: null,
      git_description: null,
      created_at: null,
      key_files_present: [],
      goal: null,
      objectives: null,
      flows: null,
      requirements: null,
      errors: [$err]
    }')
  append_catalog "$record"
}

write_deleted_record() {
  local last_record
  last_record=$(jq -rn --arg slug "$REPO_SLUG" \
    '[inputs | select(.record_type == "repo_snapshot" and .repo_slug == $slug and .collection_skipped == false)]
     | last // empty' \
    "$CATALOG_JSONL" 2>/dev/null || true)
  if [[ -z "$last_record" ]]; then
    last_record=$(jq -rn --arg slug "$REPO_SLUG" \
      '[inputs | select(.record_type == "repo_snapshot" and .repo_slug == $slug)] | last // empty' \
      "$CATALOG_JSONL" 2>/dev/null || true)
  fi

  local record
  if [[ -n "$last_record" && "$last_record" != "null" ]]; then
    record=$(jq -c \
      --arg rid "$REPORT_ID" \
      --arg gat "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      '. + {
        schema_version: "1.2.0",
        report_id: $rid,
        generated_at: $gat,
        collection_skipped: false,
        status: "deleted",
        errors: []
      }' <<< "$last_record")
  else
    record=$(jq -nc \
      --arg sv "1.2.0" \
      --arg rid "$REPORT_ID" \
      --arg gat "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      --arg own "$OWNER" \
      --arg slug "$REPO_SLUG" \
      --arg url "$REPO_URL" \
      --arg br "$BRANCH" \
      '{
        schema_version: $sv,
        record_type: "repo_snapshot",
        report_id: $rid,
        generated_at: $gat,
        collection_skipped: false,
        status: "deleted",
        owner: $own,
        repo_slug: $slug,
        repo_url: $url,
        default_branch: $br,
        head_commit_sha: "0000000000000000000000000000000000000000",
        head_commit_at: null,
        git_description: null,
        created_at: null,
        key_files_present: [],
        goal: null,
        objectives: null,
        flows: null,
        requirements: null,
        errors: []
      }')
  fi
  append_catalog "$record"
}

write_skip_record() {
  local last_record
  last_record=$(jq -rn --arg slug "$REPO_SLUG" \
    '[inputs | select(.record_type == "repo_snapshot" and .repo_slug == $slug and .collection_skipped == false)]
     | last // empty' \
    "$CATALOG_JSONL" 2>/dev/null || true)
  if [[ -z "$last_record" ]]; then
    last_record=$(jq -rn --arg slug "$REPO_SLUG" \
      '[inputs | select(.record_type == "repo_snapshot" and .repo_slug == $slug)] | last // empty' \
      "$CATALOG_JSONL" 2>/dev/null || true)
  fi
  [[ -n "$last_record" && "$last_record" != "null" ]] || fail "skip requested but no prior snapshot for $REPO_SLUG"

  local record
  record=$(jq -c \
    --arg rid "$REPORT_ID" \
    --arg gat "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg sha "$REMOTE_SHA" \
    '. + {
      schema_version: "1.2.0",
      report_id: $rid,
      generated_at: $gat,
      collection_skipped: true,
      status: (.status // "active"),
      head_commit_sha: $sha,
      errors: []
    }' <<< "$last_record")
  append_catalog "$record"
}

extract_section() {
  local keyword="$1"
  local file_content="$2"
  LC_ALL=C awk -v kw="$keyword" '
    BEGIN { kw_lower = tolower(kw) }
    p && /^#{1,4} / { exit }
    /^#{1,4} / {
      heading = $0
      sub(/^#+[[:space:]]+/, "", heading)
      hl = tolower(heading)
      if (hl == kw_lower || index(hl, kw_lower) > 0) { p = 1; next }
    }
    p { print }
  ' <<< "$file_content"
}

make_extracted_field() {
  local text="$1"
  local source_file="$2"
  local source_heading="$3"
  if [[ -z "${text//[$'\t\r\n ']/}" ]]; then
    printf 'null'
    return
  fi
  jq -nc \
    --arg text "$text" \
    --arg source_file "$source_file" \
    --arg source_heading "$source_heading" \
    '{text: $text, source_file: $source_file, source_heading: $source_heading}'
}

commit_already_recorded() {
  local sha="$1"
  [[ -f "$COMMITS_JSONL" ]] || return 1
  jq -rn \
    --arg slug "$REPO_SLUG" \
    --arg sha "$sha" \
    '[inputs | select(.record_type == "commit" and .repo_slug == $slug and .sha == $sha)] | length > 0' \
    "$COMMITS_JSONL" 2>/dev/null | grep -qx true
}

setup_git_ssh() {
  [[ -z "$SSH_KEY" ]] && return 0
  export GIT_SSH_COMMAND="ssh -i ${SSH_KEY} -o IdentitiesOnly=yes -o BatchMode=yes"
}

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

OWNER=""
REPO_SLUG=""
VISIBILITY=""
REPORT_ID=""
REPO_URL=""
GIT_HOST="${GITHUB_CATALOG_GIT_HOST:-}"
SSH_KEY="${GITHUB_CATALOG_SSH_KEY:-}"
BRANCH="main"
DATA_DIR="$REPO_ROOT/data"
LOG_FILE=""
TOMBSTONE=0
DRY_RUN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --owner|--user) OWNER="${2:?}"; shift 2 ;;
    --repo)         REPO_SLUG="${2:?}"; shift 2 ;;
    --type)         VISIBILITY="${2:?}"; shift 2 ;;
    --report-id)    REPORT_ID="${2:?}"; shift 2 ;;
    --repo-url)     REPO_URL="${2:?}"; shift 2 ;;
    --git-host)     GIT_HOST="${2:?}"; shift 2 ;;
    --ssh-key)      SSH_KEY="${2:?}"; shift 2 ;;
    --branch)       BRANCH="${2:?}"; shift 2 ;;
    --data-dir)     DATA_DIR="${2:?}"; shift 2 ;;
    --log-file)     LOG_FILE="${2:?}"; shift 2 ;;
    --tombstone)    TOMBSTONE=1; shift 1 ;;
    --dry-run)      DRY_RUN=1; shift 1 ;;
    -h|--help)      usage; exit 0 ;;
    *)              fail "unknown option: $1" ;;
  esac
done

[[ -n "$OWNER" ]]      || fail "--owner is required"
[[ -n "$REPO_SLUG" ]]  || fail "--repo is required"
[[ -n "$VISIBILITY" ]] || fail "--type is required"
if (( DRY_RUN == 0 )); then
  [[ -n "$REPORT_ID" ]] || fail "--report-id is required"
else
  REPORT_ID="${REPORT_ID:-dry-run}"
fi
[[ "$VISIBILITY" =~ ^(private|public|all)$ ]] || fail "--type must be private, public, or all"

if [[ "$DATA_DIR" == "$REPO_ROOT/data" ]]; then
  DATA_DIR="$DATA_DIR/$OWNER"
fi

if [[ -z "$LOG_FILE" ]]; then
  LOG_FILE="$REPO_ROOT/logs/github-catalog-$(date -u +%Y-%m-%d).log"
fi

mkdir -p "$DATA_DIR" "$(dirname -- "$LOG_FILE")"

CATALOG_JSONL="$DATA_DIR/git-projects-catalog.jsonl"
COMMITS_JSONL="$DATA_DIR/git-projects-commits.jsonl"

if [[ -z "$REPO_URL" ]]; then
  REPO_URL="git@${GIT_HOST:-github.com}:${OWNER}/${REPO_SLUG}.git"
fi

setup_git_ssh

log_info "START repo=$REPO_SLUG owner=$OWNER branch=$BRANCH report_id=$REPORT_ID visibility=$VISIBILITY"

if (( TOMBSTONE == 1 )); then
  if (( DRY_RUN == 1 )); then
    printf '%s\ttombstone\tdeleted\n' "$REPO_SLUG"
    exit 0
  fi
  log_info "TOMBSTONE repo=$REPO_SLUG"
  write_deleted_record
  exit 0
fi

# --- STEP 1: Resolve remote HEAD SHA ---
cmd="git ls-remote $REPO_URL refs/heads/$BRANCH"
log_cmd "$cmd"
REMOTE_SHA=""
GIT_EXIT=0
REMOTE_SHA=$(git ls-remote "$REPO_URL" "refs/heads/$BRANCH" 2>>"$LOG_FILE" | awk '{print $1; exit}') || GIT_EXIT=$?
[[ -n "$REMOTE_SHA" ]] || GIT_EXIT=${GIT_EXIT:-1}
log_result "$cmd" "$GIT_EXIT" "sha=${REMOTE_SHA:-empty}"

# --- STEP 2: Guard unreachable ---
if (( GIT_EXIT != 0 )) || [[ -z "$REMOTE_SHA" ]]; then
  if (( DRY_RUN == 1 )); then
    printf '%s\tunreachable\t%s\n' "$REPO_SLUG" "$REPO_URL"
    exit 1
  fi
  log_error "UNREACHABLE repo=$REPO_SLUG url=$REPO_URL"
  write_error_record "unreachable"
  exit 1
fi

# --- STEP 3: Query last known SHA ---
LAST_SHA=""
if [[ -f "$CATALOG_JSONL" ]]; then
  LAST_SHA=$(jq -rn --arg slug "$REPO_SLUG" \
    '[inputs | select(.record_type == "repo_snapshot" and .repo_slug == $slug)]
     | last | .head_commit_sha // empty' \
    "$CATALOG_JSONL" 2>/dev/null || true)
  if [[ "$LAST_SHA" == "0000000000000000000000000000000000000000" ]]; then
    LAST_SHA=""
  fi
fi
log_info "sentry slug=$REPO_SLUG remote=$REMOTE_SHA last=${LAST_SHA:-none}"

# --- STEP 4: Skip unchanged ---
if [[ -n "$LAST_SHA" && "$REMOTE_SHA" == "$LAST_SHA" ]]; then
  if (( DRY_RUN == 1 )); then
    printf '%s\tskip\tunchanged\n' "$REPO_SLUG"
    exit 0
  fi
  log_info "SKIP repo=$REPO_SLUG sha_unchanged=$REMOTE_SHA"
  write_skip_record
  exit 0
fi

if (( DRY_RUN == 1 )); then
  printf '%s\tcollect\tHEAD changed\n' "$REPO_SLUG"
  exit 0
fi

# --- STEP 5: Full collection ---
log_info "COLLECT repo=$REPO_SLUG old=${LAST_SHA:-none} new=$REMOTE_SHA"

TMP_CLONE="$(mktemp -d)"
cleanup() { rm -rf "$TMP_CLONE"; }
trap cleanup EXIT

cmd="git clone --bare --depth 50 --single-branch --branch $BRANCH $REPO_URL $TMP_CLONE"
log_cmd "$cmd"
t0=$(date +%s%N)
git clone --bare --depth 50 --single-branch \
  --branch "$BRANCH" "$REPO_URL" "$TMP_CLONE" 2>>"$LOG_FILE" || git_exit=$?
git_exit=${git_exit:-0}
elapsed=$(( ($(date +%s%N) - t0) / 1000000 ))
log_result "$cmd" "$git_exit" "elapsed_ms=$elapsed"
if (( git_exit != 0 )); then
  log_error "clone_failed repo=$REPO_SLUG"
  write_error_record "clone_failed"
  exit 1
fi

HEAD_SHA="$REMOTE_SHA"
HEAD_COMMIT_AT=$(git --git-dir="$TMP_CLONE" log -1 --format=%cI 2>>"$LOG_FILE" || true)
CREATED_AT=$(git --git-dir="$TMP_CLONE" log --reverse --format=%cI 2>>"$LOG_FILE" | head -1 || true)

GIT_DESCRIPTION=$(git --git-dir="$TMP_CLONE" config --get remote.origin.description 2>/dev/null || true)
if [[ -z "$GIT_DESCRIPTION" && -f "$TMP_CLONE/description" ]]; then
  GIT_DESCRIPTION=$(LC_ALL=C head -1 "$TMP_CLONE/description" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
fi
[[ -n "$GIT_DESCRIPTION" ]] || GIT_DESCRIPTION=null

KEY_FILES_SENTINEL=(
  "README.md" "PROJECT.md" "INSTALL.md" "GOALS.md"
  "REQUIREMENTS.md" "APP-REQS.md" "Makefile" ".github/workflows"
  "Dockerfile" "package.json" "go.mod" "Cargo.toml" "pyproject.toml"
)

tree_paths=$(git --git-dir="$TMP_CLONE" ls-tree -r HEAD --name-only 2>>"$LOG_FILE" || true)
key_files_json="[]"
for f in "${KEY_FILES_SENTINEL[@]}"; do
  if printf '%s\n' "$tree_paths" | grep -qxF "$f" || \
     printf '%s\n' "$tree_paths" | grep -qF "${f}/"; then
    key_files_json=$(jq --arg f "$f" '. + [$f]' <<< "$key_files_json")
  fi
done

readme_content=$(git --git-dir="$TMP_CLONE" show "HEAD:README.md" 2>/dev/null || true)
goal_text=$(extract_section "GOAL" "$readme_content" | LC_ALL=C sed '/^[[:space:]]*$/d')
objectives_text=$(extract_section "OBJECTIVES" "$readme_content" | LC_ALL=C sed '/^[[:space:]]*$/d')
flows_text=$(extract_section "Typical Workflows" "$readme_content" | LC_ALL=C sed '/^[[:space:]]*$/d')
if [[ -z "${flows_text//[$'\t\r\n ']/}" ]]; then
  flows_text=$(extract_section "Workflows" "$readme_content" | LC_ALL=C sed '/^[[:space:]]*$/d')
fi
requirements_text=$(extract_section "REQUIREMENTS" "$readme_content" | LC_ALL=C sed '/^[[:space:]]*$/d')

GOAL_OBJ=$(make_extracted_field "$goal_text" "README.md" "GOAL")
OBJ_OBJ=$(make_extracted_field "$objectives_text" "README.md" "OBJECTIVES")
FLOW_OBJ=$(make_extracted_field "$flows_text" "README.md" "Typical Workflows")
REQ_OBJ=$(make_extracted_field "$requirements_text" "README.md" "REQUIREMENTS")

while IFS= read -r commit_sha; do
  [[ -n "$commit_sha" ]] || continue
  commit_already_recorded "$commit_sha" && continue

  committed_at=$(git --git-dir="$TMP_CLONE" log -1 --format=%cI "$commit_sha" 2>>"$LOG_FILE" || true)
  author_name=$(git --git-dir="$TMP_CLONE" log -1 --format=%an "$commit_sha" 2>>"$LOG_FILE" || true)
  author_email=$(git --git-dir="$TMP_CLONE" log -1 --format=%ae "$commit_sha" 2>>"$LOG_FILE" || true)
  message=$(git --git-dir="$TMP_CLONE" log -1 --format=%s "$commit_sha" 2>>"$LOG_FILE" || true)
  files_changed=$(git --git-dir="$TMP_CLONE" diff-tree --no-commit-id -r --name-only "$commit_sha" 2>>"$LOG_FILE" | wc -l | tr -d ' ')
  short_sha="${commit_sha:0:7}"

  commit_record=$(jq -nc \
    --arg sv "1.2.0" \
    --arg rid "$REPORT_ID" \
    --arg gat "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg own "$OWNER" \
    --arg slug "$REPO_SLUG" \
    --arg url "$REPO_URL" \
    --arg br "$BRANCH" \
    --arg sha "$commit_sha" \
    --arg short "$short_sha" \
    --arg cat "$committed_at" \
    --arg an "$author_name" \
    --arg ae "$author_email" \
    --arg msg "$message" \
    --argjson fc "${files_changed:-0}" \
    '{
      schema_version: $sv,
      record_type: "commit",
      report_id: $rid,
      generated_at: $gat,
      status: "active",
      owner: $own,
      repo_slug: $slug,
      repo_url: $url,
      default_branch: $br,
      sha: $sha,
      short_sha: $short,
      committed_at: (if $cat == "" then null else $cat end),
      author_name: (if $an == "" then null else $an end),
      author_email: (if $ae == "" then null else $ae end),
      message: $msg,
      files_changed: $fc
    }')
  append_commit "$commit_record"
done < <(git --git-dir="$TMP_CLONE" log --format=%H 2>>"$LOG_FILE")

if [[ "$GIT_DESCRIPTION" == "null" ]]; then
  desc_arg=null
else
  desc_arg="$GIT_DESCRIPTION"
fi
if [[ -z "$HEAD_COMMIT_AT" ]]; then head_at_arg=null; else head_at_arg="$HEAD_COMMIT_AT"; fi
if [[ -z "$CREATED_AT" ]]; then created_arg=null; else created_arg="$CREATED_AT"; fi

record=$(jq -nc \
  --arg sv "1.2.0" \
  --arg rid "$REPORT_ID" \
  --arg gat "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg own "$OWNER" \
  --arg slug "$REPO_SLUG" \
  --arg url "$REPO_URL" \
  --arg br "$BRANCH" \
  --arg sha "$HEAD_SHA" \
  --arg sha_t "$head_at_arg" \
  --arg desc "$desc_arg" \
  --arg cr "$created_arg" \
  --argjson kf "$key_files_json" \
  --argjson goal "$GOAL_OBJ" \
  --argjson objectives "$OBJ_OBJ" \
  --argjson flows "$FLOW_OBJ" \
  --argjson requirements "$REQ_OBJ" \
  '{
    schema_version: $sv,
    record_type: "repo_snapshot",
    report_id: $rid,
    generated_at: $gat,
    collection_skipped: false,
    status: "active",
    owner: $own,
    repo_slug: $slug,
    repo_url: $url,
    default_branch: $br,
    head_commit_sha: $sha,
    head_commit_at: (if $sha_t == "null" then null else $sha_t end),
    git_description: (if $desc == "null" then null else $desc end),
    created_at: (if $cr == "null" then null else $cr end),
    key_files_present: $kf,
    goal: $goal,
    objectives: $objectives,
    flows: $flows,
    requirements: $requirements,
    errors: []
  }')

append_catalog "$record"
log_info "DONE repo=$REPO_SLUG sha=$HEAD_SHA"