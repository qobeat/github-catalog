#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
github-catalog-datafetcher.sh - fetch one GitHub repo catalog snapshot into JSONL

Required:
  --owner NAME              GitHub owner
  --repo NAME               Repository slug
  --type private|public|all Visibility recorded in snapshot filter
  --report-id ID            UTC report id

Options:
  --data-dir DIR            Generated JSONL dir (default: data/github-catalog)
  --cache-dir DIR           Cache dir (default: .cache/github-catalog)
  --collector PATH          Existing Python collector (default: scripts/catalog_qobeat_repos.py)
  --mock-catalog-json PATH  Offline test mode: read repo payload from existing catalog JSON
  --no-line-counts          Pass through to collector
  --delay-ms N              Pass through to collector
  --no-skip-if-unchanged    Always append as collected even if same HEAD is already known
  -h, --help                Show help
EOF
}

ts() { date -u +%Y-%m-%dT%H:%M:%SZ; }
log() { printf '%s %s\n' "$(ts)" "$*" >&2; }
fail() { log "ERROR $*"; exit 2; }

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
OWNER="qobeat"
REPO=""
VISIBILITY="private"
REPORT_ID=""
DATA_DIR="$REPO_ROOT/data/github-catalog"
CACHE_DIR="$REPO_ROOT/.cache/github-catalog"
COLLECTOR="$SCRIPT_DIR/catalog_qobeat_repos.py"
MOCK_CATALOG_JSON=""
NO_LINE_COUNTS=0
DELAY_MS=0
SKIP_IF_UNCHANGED=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --owner|--user) OWNER="${2:?}"; shift 2 ;;
    --repo) REPO="${2:?}"; shift 2 ;;
    --type) VISIBILITY="${2:?}"; shift 2 ;;
    --report-id) REPORT_ID="${2:?}"; shift 2 ;;
    --data-dir) DATA_DIR="${2:?}"; shift 2 ;;
    --cache-dir) CACHE_DIR="${2:?}"; shift 2 ;;
    --collector) COLLECTOR="${2:?}"; shift 2 ;;
    --mock-catalog-json) MOCK_CATALOG_JSON="${2:?}"; shift 2 ;;
    --no-line-counts) NO_LINE_COUNTS=1; shift ;;
    --delay-ms) DELAY_MS="${2:?}"; shift 2 ;;
    --no-skip-if-unchanged) SKIP_IF_UNCHANGED=0; shift ;;
    -h|--help) usage; exit 0 ;;
    *) fail "unknown option: $1" ;;
  esac
done

[[ -n "$REPO" ]] || fail "--repo is required"
[[ -n "$REPORT_ID" ]] || fail "--report-id is required"
[[ "$VISIBILITY" =~ ^(private|public|all)$ ]] || fail "--type must be private, public, or all"
mkdir -p "$DATA_DIR" "$CACHE_DIR"
SNAPSHOTS_JSONL="$DATA_DIR/catalog-snapshots.jsonl"
COMMITS_JSONL="$DATA_DIR/repo-commits.jsonl"
LOCK_FILE="$DATA_DIR/.append.lock"

TMP_DOC="$(mktemp)"
TMP_HEAD="$(mktemp)"
TMP_RECORD="$(mktemp)"
cleanup() { rm -f "$TMP_DOC" "$TMP_HEAD" "$TMP_RECORD"; }
trap cleanup EXIT

if [[ -n "$MOCK_CATALOG_JSON" ]]; then
  [[ -f "$MOCK_CATALOG_JSON" ]] || fail "mock catalog JSON not found: $MOCK_CATALOG_JSON"
  cp "$MOCK_CATALOG_JSON" "$TMP_DOC"
  printf '[]\n' > "$TMP_HEAD"
else
  command -v gh >/dev/null 2>&1 || fail "gh is required for live mode"
  [[ -f "$COLLECTOR" ]] || fail "collector not found: $COLLECTOR"
  args=(python3 "$COLLECTOR" --owner "$OWNER" --repo "$REPO" --cache-dir "$CACHE_DIR" --stdout-json)
  (( NO_LINE_COUNTS == 1 )) && args+=(--no-line-counts)
  (( DELAY_MS > 0 )) && args+=(--delay-ms "$DELAY_MS")
  "${args[@]}" > "$TMP_DOC"
  branch="$(python3 - "$TMP_DOC" "$REPO" <<'PY'
import json, sys
doc = json.load(open(sys.argv[1], encoding='utf-8'))
repo = sys.argv[2]
items = doc.get('repos', []) if isinstance(doc, dict) else []
match = next((r for r in items if r.get('slug') == repo or r.get('name') == repo), items[0] if items else {})
print(match.get('default_branch') or 'main')
PY
)"
  gh api "repos/$OWNER/$REPO/commits?sha=$branch&per_page=1" > "$TMP_HEAD" 2>/dev/null || printf '[]\n' > "$TMP_HEAD"
fi

python3 - "$TMP_DOC" "$TMP_HEAD" "$SNAPSHOTS_JSONL" "$OWNER" "$REPO" "$VISIBILITY" "$REPORT_ID" "$SKIP_IF_UNCHANGED" > "$TMP_RECORD" <<'PY'
import hashlib, json, pathlib, sys
from datetime import datetime, timezone

doc_path, head_path, snapshots_path, owner, repo_name, visibility, report_id, skip_s = sys.argv[1:9]
skip_if_unchanged = skip_s == '1'
now = datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
doc = json.load(open(doc_path, encoding='utf-8'))
repos = doc.get('repos', []) if isinstance(doc, dict) else []
repo = next((r for r in repos if r.get('slug') == repo_name or r.get('name') == repo_name), None)
if repo is None:
    raise SystemExit(f'repo not found in collector output: {repo_name}')
slug = repo.get('slug') or repo.get('name') or repo_name
repo['slug'] = slug
repo.setdefault('url', f'https://github.com/{owner}/{slug}')
repo.setdefault('default_branch', 'main')
repo.setdefault('archetype', 'other')
repo.setdefault('bootstrap', 'unknown')
repo.setdefault('files_total', 0)
repo.setdefault('text_files', 0)
repo.setdefault('binary_files', 0)
repo.setdefault('top_level', [])
repo.setdefault('execution_flows', [])
repo.setdefault('flow_sources', [])
repo.setdefault('errors', [])
repo.setdefault('key_files_present', [])
repo.setdefault('requirements', None)

head_sha = repo.get('head_commit_sha')
head_at = repo.get('head_commit_at') or repo.get('pushed_at') or repo.get('updated_at')
try:
    head_doc = json.load(open(head_path, encoding='utf-8'))
    if isinstance(head_doc, list) and head_doc:
        head_sha = head_doc[0].get('sha') or head_sha
        head_at = (((head_doc[0].get('commit') or {}).get('committer') or {}).get('date')) or head_at
except Exception:
    pass
if not head_sha:
    seed = '|'.join([slug, str(repo.get('pushed_at') or ''), str(repo.get('updated_at') or '')])
    head_sha = hashlib.sha1(seed.encode('utf-8')).hexdigest()
repo['head_commit_sha'] = head_sha
repo['head_commit_at'] = head_at

last = None
sp = pathlib.Path(snapshots_path)
if sp.exists():
    with sp.open(encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                rec = json.loads(line)
            except json.JSONDecodeError:
                continue
            if rec.get('record_type') == 'repo_snapshot' and rec.get('repo_slug') == slug:
                last = rec

collection_skipped = False
if skip_if_unchanged and last and last.get('head_commit_sha') == head_sha:
    collection_skipped = True
    repo = last.get('repo') or repo
    repo['head_commit_sha'] = head_sha
    repo['head_commit_at'] = head_at

record = {
    'schema_version': '1.0.0',
    'record_type': 'repo_snapshot',
    'report_id': report_id,
    'generated_at': now,
    'owner': owner,
    'filter': {'visibility': visibility, 'non_empty': True},
    'repo_slug': slug,
    'repo_url': repo.get('url'),
    'default_branch': repo.get('default_branch') or 'main',
    'head_commit_sha': head_sha,
    'head_commit_at': head_at,
    'collection_skipped': collection_skipped,
    'repo': repo,
    'errors': repo.get('errors', []),
}
print(json.dumps(record, ensure_ascii=False, separators=(',', ':')))
PY

append_line() {
  local line_file="$1"
  local target="$2"
  if command -v flock >/dev/null 2>&1; then
    (
      flock -x 9
      cat "$line_file" >> "$target"
    ) 9>"$LOCK_FILE"
  else
    cat "$line_file" >> "$target"
  fi
}

append_line "$TMP_RECORD" "$SNAPSHOTS_JSONL"
: > "$COMMITS_JSONL"
log "DONE $REPO snapshot=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["collection_skipped"])' "$TMP_RECORD") jsonl=$SNAPSHOTS_JSONL"
