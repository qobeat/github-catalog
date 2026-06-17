#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
github-catalog-orchestrator.sh - run GitHub catalog datafetchers in parallel

Required for live mode:
  --user, --owner NAME_OR_URL     GitHub owner, e.g. qobeat or https://github.com/qobeat
  --repos GLOB                    Repository glob, e.g. '*' or 'ados-*'
  --type private|public|all       Visibility filter

Useful options:
  --parallel N                    Concurrent workers (default: 5)
  --limit N                       Max repos to process (0 = no limit)
  --data-dir DIR                  Generated JSONL dir (default: data/github-catalog)
  --cache-dir DIR                 Cache dir (default: .cache/github-catalog)
  --report-id ID                  UTC report id (default: now)
  --fetcher PATH                  Datafetcher script path
  --collector PATH                Existing Python collector path
  --repo-list-file PATH           Offline/test mode: newline-separated repo slugs
  --mock-catalog-json PATH        Offline/test mode: list/fetch repos from existing catalog JSON
  --no-line-counts                Pass through to collector
  --delay-ms N                    Pass through to collector
  -h, --help                      Show help

Examples:
  scripts/github-catalog-orchestrator.sh --user qobeat --repos 'ados-*' --type private --parallel 5 --no-line-counts
  scripts/github-catalog-orchestrator.sh --mock-catalog-json qobeat-private-repos-smoke.json --repos 'ados-*' --type private --parallel 2 --limit 3 --data-dir /tmp/github-catalog-data
EOF
}

ts() { date -u +%Y-%m-%dT%H:%M:%SZ; }
log() { printf '%s %s\n' "$(ts)" "$*" >&2; }
fail() { log "ERROR $*"; exit 2; }

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
OWNER="qobeat"
REPOS_GLOB=""
VISIBILITY=""
PARALLEL="5"
LIMIT="0"
DATA_DIR="$REPO_ROOT/data/github-catalog"
CACHE_DIR="$REPO_ROOT/.cache/github-catalog"
REPORT_ID="$(ts)"
FETCHER="$SCRIPT_DIR/github-catalog-datafetcher.sh"
COLLECTOR="$SCRIPT_DIR/catalog_qobeat_repos.py"
REPO_LIST_FILE=""
MOCK_CATALOG_JSON=""
NO_LINE_COUNTS=0
DELAY_MS=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --user|--owner) OWNER="${2:?}"; shift 2 ;;
    --repos) REPOS_GLOB="${2:?}"; shift 2 ;;
    --type) VISIBILITY="${2:?}"; shift 2 ;;
    --parallel) PARALLEL="${2:?}"; shift 2 ;;
    --limit) LIMIT="${2:?}"; shift 2 ;;
    --data-dir) DATA_DIR="${2:?}"; shift 2 ;;
    --cache-dir) CACHE_DIR="${2:?}"; shift 2 ;;
    --report-id) REPORT_ID="${2:?}"; shift 2 ;;
    --fetcher) FETCHER="${2:?}"; shift 2 ;;
    --collector) COLLECTOR="${2:?}"; shift 2 ;;
    --repo-list-file) REPO_LIST_FILE="${2:?}"; shift 2 ;;
    --mock-catalog-json) MOCK_CATALOG_JSON="${2:?}"; shift 2 ;;
    --no-line-counts) NO_LINE_COUNTS=1; shift ;;
    --delay-ms) DELAY_MS="${2:?}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) fail "unknown option: $1" ;;
  esac
done

[[ -n "$REPOS_GLOB" ]] || fail "--repos is required"
[[ -n "$VISIBILITY" ]] || fail "--type is required"
[[ "$VISIBILITY" =~ ^(private|public|all)$ ]] || fail "--type must be private, public, or all"
[[ "$PARALLEL" =~ ^[0-9]+$ ]] && (( PARALLEL >= 1 )) || fail "--parallel must be >= 1"
[[ "$LIMIT" =~ ^[0-9]+$ ]] || fail "--limit must be >= 0"
[[ -x "$FETCHER" ]] || fail "fetcher not executable: $FETCHER"
mkdir -p "$DATA_DIR" "$CACHE_DIR"

OWNER="$(python3 - "$OWNER" <<'PY'
import sys
from urllib.parse import urlparse
v = sys.argv[1].strip().rstrip('/')
if 'github.com' in v:
    parsed = urlparse(v if '://' in v else 'https://' + v)
    print(parsed.path.strip('/').split('/')[0])
else:
    print(v)
PY
)"

list_repos_from_mock() {
  python3 - "$MOCK_CATALOG_JSON" "$REPOS_GLOB" "$LIMIT" <<'PY'
import fnmatch, json, sys
path, glob, limit_s = sys.argv[1:4]
limit = int(limit_s)
doc = json.load(open(path, encoding='utf-8'))
repos = [r.get('slug') or r.get('name') for r in doc.get('repos', [])]
repos = [r for r in repos if r and fnmatch.fnmatch(r, glob)]
if limit > 0:
    repos = repos[:limit]
for r in repos:
    print(r)
PY
}

list_repos_from_file() {
  python3 - "$REPO_LIST_FILE" "$REPOS_GLOB" "$LIMIT" <<'PY'
import fnmatch, sys
path, glob, limit_s = sys.argv[1:4]
limit = int(limit_s)
out = []
for line in open(path, encoding='utf-8'):
    line = line.strip()
    if not line or line.startswith('#'):
        continue
    repo = line.split()[0]
    if fnmatch.fnmatch(repo, glob):
        out.append(repo)
if limit > 0:
    out = out[:limit]
print('\n'.join(out))
PY
}

list_repos_live() {
  command -v gh >/dev/null 2>&1 || fail "gh is required for live mode"
  [[ -f "$COLLECTOR" ]] || fail "collector not found: $COLLECTOR"
  PYTHONPATH="$SCRIPT_DIR" python3 - "$OWNER" "$VISIBILITY" "$REPOS_GLOB" "$LIMIT" <<'PY'
import sys
import catalog_qobeat_repos as catalog
owner, visibility, glob_pattern, limit_s = sys.argv[1:5]
limit = int(limit_s)
gh = catalog.GhClient('orchestrator-list')
repos = catalog.list_repos(gh, owner, visibility=visibility, glob_pattern=glob_pattern, only_repo=None, non_empty=True)
if limit > 0:
    repos = repos[:limit]
for repo in repos:
    print(repo.get('name'))
PY
}

if [[ -n "$MOCK_CATALOG_JSON" ]]; then
  mapfile -t REPOS < <(list_repos_from_mock)
elif [[ -n "$REPO_LIST_FILE" ]]; then
  mapfile -t REPOS < <(list_repos_from_file)
else
  mapfile -t REPOS < <(list_repos_live)
fi

((${#REPOS[@]} > 0)) || fail "no repositories matched"
log "RUN report_id=$REPORT_ID owner=$OWNER repos=${#REPOS[@]} parallel=$PARALLEL data_dir=$DATA_DIR"

running=0
failures=0
for repo in "${REPOS[@]}"; do
  args=("$FETCHER" --owner "$OWNER" --repo "$repo" --type "$VISIBILITY" --report-id "$REPORT_ID" --data-dir "$DATA_DIR" --cache-dir "$CACHE_DIR" --collector "$COLLECTOR")
  (( NO_LINE_COUNTS == 1 )) && args+=(--no-line-counts)
  (( DELAY_MS > 0 )) && args+=(--delay-ms "$DELAY_MS")
  [[ -n "$MOCK_CATALOG_JSON" ]] && args+=(--mock-catalog-json "$MOCK_CATALOG_JSON")
  log "DISPATCH $repo"
  "${args[@]}" &
  ((running+=1))
  if (( running >= PARALLEL )); then
    if ! wait -n; then ((failures+=1)); fi
    running=$((running - 1))
  fi
done
while (( running > 0 )); do
  if ! wait -n; then ((failures+=1)); fi
  running=$((running - 1))
done

if (( failures > 0 )); then
  fail "$failures worker(s) failed"
fi
log "DONE report_id=$REPORT_ID snapshots=$DATA_DIR/catalog-snapshots.jsonl"
