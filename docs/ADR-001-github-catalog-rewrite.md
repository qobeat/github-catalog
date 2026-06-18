# ADR-001: github-catalog — Pure Bash/jq/git Rewrite

**Status:** Proposed  
**Date:** 2026-06-17  
**Environment:** WSL2 · Linux 6.6.114.1-microsoft-standard-WSL2 · x86\_64 · Bash 5.0+ · jq 1.7  
**Replaces:** Python + `gh`-CLI implementation in `github-catalog.zip`

---

## Context

The reference implementation has four structural problems that motivate a clean rewrite:

| Problem | Impact |
|---|---|
| Hard dependency on `gh` CLI (GitHub-specific auth layer) | Not portable; breaks in airgapped or non-GitHub environments |
| Hard dependency on Python + stdlib | Adds runtime requirement; `catalog_qobeat_repos.py` is tightly coupled to one owner |
| No sentry logic — always re-fetches every repo | Expensive on large catalogs; API rate-limit risk |
| Orchestrator has no progress feedback and logs to stderr only | No audit trail; no structured log file |

The goal is a standalone, self-contained tool that works against **any** git remote (GitHub, GitLab, Gitea, bare SSH remotes) using only: **Bash 5.0+, jq 1.7, standard git, and POSIX tools.**

---

## Decision

Rewrite `github-catalog` from scratch as three Bash scripts + one JSON Schema document + two append-only JSONL data streams.

```
github-catalog/
├── scripts/
│   ├── github-catalog-orchestrator.sh   # parallel dispatch + progress bar
│   ├── github-catalog-datafetcher.sh    # single-repo sentry + collection
│   └── github-catalog-report.sh         # pure-jq markdown generator
├── data/
│   ├── git-projects-catalog.jsonl        # repo snapshots (gitignored)
│   └── git-projects-commits.jsonl        # commit records  (gitignored)
├── reports/
│   └── latest.md                          # generated report (gitignored)
├── logs/
│   └── github-catalog-YYYY-MM-DD.log      # timestamped run log (gitignored)
├── docs/
│   └── github-catalog.schema.json         # tracked canonical schema
├── README.md
└── .gitignore
```

---

## Options Considered

### Option A: Keep Python + `gh` (rejected)

| Dimension | Assessment |
|---|---|
| Portability | Low — requires `gh` auth, Python runtime |
| Sentry logic | Not implemented; would require Python additions |
| LLM parseability | Medium — schema exists but Python inline strings are opaque |
| Maintenance | High — two runtimes, tight owner coupling |

**Rejected because:** `gh` is GitHub-only, Python requirement is non-trivial in minimal WSL environments, and patching sentry logic into the existing Python collector would be a large invasive change.

### Option B: `curl` + GitHub REST API directly (rejected)

| Dimension | Assessment |
|---|---|
| Portability | Low — GitHub-only, requires `GITHUB_TOKEN` management |
| Auth complexity | High — token rotation, scoping, expiry |
| Rate limits | Hard 5000 req/hr ceiling |
| Offline/airgap | Impossible |

**Rejected because:** Adds auth token surface area, still GitHub-specific, and `git ls-remote` already gives us HEAD SHA without any token for public repos or with standard SSH keys for private ones.

### Option C: SQLite database (rejected)

| Dimension | Assessment |
|---|---|
| Query power | High |
| Portability | Low — requires `sqlite3` binary |
| LLM parseability | Low — binary format, not human-readable |
| Append-only audit trail | Requires careful schema design |

**Rejected because:** JSONL is natively parseable by every LLM, every language, and every POSIX pipeline. A database is overkill for a catalog of dozens to hundreds of repos.

### Option D (chosen): Pure Bash 5.0+ / jq 1.7 / git

| Dimension | Assessment |
|---|---|
| Portability | High — Bash + git + jq available in any Linux/WSL environment |
| LLM parseability | High — JSONL with explicit field descriptions |
| Sentry logic | Native via `git ls-remote` + `jq` |
| Audit trail | Structured timestamped log file |
| Parallelism | Bash job control with `wait -n` (Bash 5.0+) |

---

## Consequences

**What becomes easier:**
- Running the tool in airgapped or non-GitHub environments (any git remote works)
- LLM agents consuming, updating, or producing new catalog records (schema is self-documenting)
- Auditing exactly which git commands ran and what they returned (structured log)
- Incremental updates — unchanged repos are skipped in milliseconds

**What becomes harder:**
- Extracting semantic fields (GOAL, OBJECTIVES, REQUIREMENTS) without Python's `re` — requires careful `awk`/`sed` patterns
- Handling non-UTF-8 repo content — must add `LC_ALL=C` guards in text extraction

**What to revisit:**
- If catalog grows beyond ~1000 repos, the `jq -rn '[inputs | ...]'` sentry query loads the entire JSONL into memory — at that scale, switch to `grep` pre-filter + tail pattern
- The `flock`-based JSONL append is safe for parallel writes on the same host; distributed writes would require a different strategy

---

## Schemas

### Schema A — `git-projects-catalog.jsonl` (repo\_snapshot record)

One line appended per repo per run. LLM agents should read `record_type` first to identify the record, then work top-down. Every field uses snake\_case with unambiguous names.

```json
{
  "schema_version": "1.0.0",
  "record_type": "repo_snapshot",
  "report_id": "2026-06-17T12:00:00Z",
  "generated_at": "2026-06-17T12:00:04Z",
  "collection_skipped": false,

  "owner": "qobeat",
  "repo_slug": "my-unix-scripts",
  "repo_url": "git@github.com:qobeat/my-unix-scripts.git",
  "default_branch": "main",
  "head_commit_sha": "a3f8c21d9e4b07625f1c3a8d0e7b92641fd5c8e1",
  "head_commit_at": "2026-06-16T22:14:07Z",

  "git_description": "Small CLI toolbox for WSL and Ubuntu environments",
  "created_at": "2023-11-01T09:30:00Z",

  "key_files_present": [
    "README.md",
    "PROJECT.md",
    "INSTALL.md",
    "scripts/install.sh",
    ".gitignore"
  ],

  "goal": {
    "text": "Create a repeatable, local-first catalog of GitHub repositories for a selected owner without cloning and without LLM summarization.",
    "source_file": "README.md",
    "source_heading": "GOAL"
  },
  "objectives": {
    "text": "1. Collect repository identity and metadata\n2. Extract self-defined semantics verbatim\n3. Preserve history in append-only JSONL",
    "source_file": "README.md",
    "source_heading": "OBJECTIVES"
  },
  "flows": {
    "text": "install.sh --mode symlink → scans scripts/ for shebangs → creates symlinks in ~/.local/bin → commands available on PATH",
    "source_file": "README.md",
    "source_heading": "Typical Workflows"
  },
  "requirements": {
    "text": "Must support --user/--owner, --repos glob, --type private|public|all, --parallel, --limit, --data-dir, --cache-dir, --report-id.",
    "source_file": "README.md",
    "source_heading": "REQUIREMENTS"
  },

  "errors": []
}
```

**Field reference for LLM agents:**

| Field | Type | Description |
|---|---|---|
| `schema_version` | string `"1.0.0"` | Semver; increment minor on additive changes, major on breaking |
| `record_type` | const `"repo_snapshot"` | Discriminator — always check this first |
| `report_id` | ISO 8601 UTC | The run that produced this record; shared across all repos in one orchestrator run |
| `generated_at` | ISO 8601 UTC | Exact moment this individual record was written |
| `collection_skipped` | boolean | `true` = HEAD SHA unchanged; catalog fields are copied from last full record |
| `owner` | string | Git host owner/org (no URL, no slashes) |
| `repo_slug` | string | Repository short name only (no `owner/` prefix) |
| `repo_url` | string | Full clone URL (SSH or HTTPS) |
| `default_branch` | string | Branch that HEAD points to |
| `head_commit_sha` | 40-char hex | Current HEAD at collection time; key field for sentry deduplication |
| `head_commit_at` | ISO 8601 UTC or null | Commit timestamp of HEAD |
| `git_description` | string or null | Value of `git config --get remote.origin.description` or first line of `.git/description` |
| `created_at` | ISO 8601 UTC or null | Date of first commit (`git log --reverse --format=%cI` | head -1) |
| `key_files_present` | string array | Files found via `git ls-tree HEAD --name-only -r` filtered against a known sentinel list |
| `goal` | extracted\_field or null | Verbatim text under GOAL heading; null if not found |
| `objectives` | extracted\_field or null | Verbatim text under OBJECTIVES heading; null if not found |
| `flows` | extracted\_field or null | Execution flow description; null if not found |
| `requirements` | extracted\_field or null | Verbatim requirements text; null if not found |
| `errors` | string array | Non-fatal errors encountered during collection |

**`extracted_field` sub-object:**

```json
{
  "text": "verbatim content copied from the source file, no summarization",
  "source_file": "README.md",
  "source_heading": "### GOAL"
}
```

> **LLM agent note:** When updating a record, preserve `source_file` and `source_heading` from the original. When producing a new record, set `source_file` to `"llm-generated"` and `source_heading` to `"n/a"` to distinguish agent-produced content from extracted content.

---

### Schema B — `git-projects-commits.jsonl` (commit record)

One line appended per new commit discovered. Deduplicated on `(repo_slug, sha)` before append.

```json
{
  "schema_version": "1.0.0",
  "record_type": "commit",
  "report_id": "2026-06-17T12:00:00Z",
  "generated_at": "2026-06-17T12:00:06Z",

  "owner": "qobeat",
  "repo_slug": "my-unix-scripts",
  "repo_url": "git@github.com:qobeat/my-unix-scripts.git",
  "default_branch": "main",

  "sha": "a3f8c21d9e4b07625f1c3a8d0e7b92641fd5c8e1",
  "short_sha": "a3f8c21",
  "committed_at": "2026-06-16T22:14:07Z",
  "author_name": "Alex",
  "author_email": "alex@example.com",
  "message": "feat: add github-catalog orchestrator with progress bar",
  "files_changed": 4
}
```

**Field reference:**

| Field | Type | Description |
|---|---|---|
| `record_type` | const `"commit"` | Discriminator |
| `sha` | 40-char hex | Full commit hash; primary deduplication key with `repo_slug` |
| `short_sha` | 7-char string | `sha[0:7]` — for display use only |
| `committed_at` | ISO 8601 UTC | `git log --format=%cI` value, converted to UTC |
| `author_name` | string | `git log --format=%an` |
| `author_email` | string | `git log --format=%ae` |
| `message` | string | First line only (`git log --format=%s`) — no multi-line body |
| `files_changed` | integer | `git diff-tree --no-commit-id -r --name-only <sha> \| wc -l` |

---

### Canonical JSON Schema document (`docs/github-catalog.schema.json`)

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "github-catalog/schema/1.0.0",
  "title": "GitHub Catalog JSONL Record Schema",
  "description": "Schema for two append-only JSONL streams: git-projects-catalog.jsonl and git-projects-commits.jsonl. Each line is one JSON object matching either repo_snapshot or commit.",
  "oneOf": [
    { "$ref": "#/$defs/repo_snapshot" },
    { "$ref": "#/$defs/commit" }
  ],
  "$defs": {
    "iso_datetime": {
      "type": "string",
      "pattern": "^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}Z$",
      "description": "UTC timestamp in ISO 8601 format with Z suffix"
    },
    "sha40": {
      "type": "string",
      "pattern": "^[0-9a-f]{40}$",
      "description": "Full 40-character lowercase git commit SHA"
    },
    "extracted_field": {
      "description": "Verbatim text extracted from a source file. Never summarized or rewritten. LLM agents: when producing records, set source_file to 'llm-generated'.",
      "type": "object",
      "required": ["text", "source_file", "source_heading"],
      "additionalProperties": false,
      "properties": {
        "text":           { "type": "string", "description": "Verbatim content, no summarization" },
        "source_file":    { "type": "string", "description": "Relative path to the file this was extracted from" },
        "source_heading": { "type": "string", "description": "Exact heading or key under which the text appeared" }
      }
    },
    "envelope": {
      "description": "Fields present on every record regardless of type",
      "type": "object",
      "required": ["schema_version", "record_type", "report_id", "generated_at"],
      "properties": {
        "schema_version": { "type": "string", "pattern": "^\\d+\\.\\d+\\.\\d+$" },
        "record_type":    { "type": "string", "enum": ["repo_snapshot", "commit"] },
        "report_id":      { "$ref": "#/$defs/iso_datetime", "description": "Run ID shared by all records from one orchestrator invocation" },
        "generated_at":   { "$ref": "#/$defs/iso_datetime", "description": "Moment this specific record was written" }
      }
    },
    "repo_snapshot": {
      "allOf": [{ "$ref": "#/$defs/envelope" }],
      "type": "object",
      "required": [
        "schema_version", "record_type", "report_id", "generated_at",
        "collection_skipped", "owner", "repo_slug", "repo_url",
        "default_branch", "head_commit_sha", "key_files_present", "errors"
      ],
      "additionalProperties": false,
      "properties": {
        "schema_version":   { "type": "string" },
        "record_type":      { "const": "repo_snapshot" },
        "report_id":        { "$ref": "#/$defs/iso_datetime" },
        "generated_at":     { "$ref": "#/$defs/iso_datetime" },
        "collection_skipped": {
          "type": "boolean",
          "description": "true when HEAD SHA matches last recorded snapshot; catalog fields are copied verbatim from that prior record"
        },
        "owner":            { "type": "string", "minLength": 1, "description": "Git host owner or organization, no slashes" },
        "repo_slug":        { "type": "string", "minLength": 1, "description": "Repository short name only, no owner prefix" },
        "repo_url":         { "type": "string", "description": "Full SSH or HTTPS clone URL" },
        "default_branch":   { "type": "string", "minLength": 1 },
        "head_commit_sha":  { "$ref": "#/$defs/sha40" },
        "head_commit_at":   { "type": ["string", "null"] },
        "git_description":  { "type": ["string", "null"], "description": "From .git/description or git config" },
        "created_at":       { "type": ["string", "null"], "description": "Date of first commit via git log --reverse" },
        "key_files_present": {
          "type": "array", "items": { "type": "string" },
          "description": "Files from a sentinel list found via git ls-tree"
        },
        "goal":             { "oneOf": [{ "$ref": "#/$defs/extracted_field" }, { "type": "null" }] },
        "objectives":       { "oneOf": [{ "$ref": "#/$defs/extracted_field" }, { "type": "null" }] },
        "flows":            { "oneOf": [{ "$ref": "#/$defs/extracted_field" }, { "type": "null" }] },
        "requirements":     { "oneOf": [{ "$ref": "#/$defs/extracted_field" }, { "type": "null" }] },
        "errors":           { "type": "array", "items": { "type": "string" } }
      }
    },
    "commit": {
      "allOf": [{ "$ref": "#/$defs/envelope" }],
      "type": "object",
      "required": [
        "schema_version", "record_type", "report_id", "generated_at",
        "owner", "repo_slug", "repo_url", "default_branch",
        "sha", "short_sha", "committed_at", "message", "files_changed"
      ],
      "additionalProperties": false,
      "properties": {
        "schema_version": { "type": "string" },
        "record_type":    { "const": "commit" },
        "report_id":      { "$ref": "#/$defs/iso_datetime" },
        "generated_at":   { "$ref": "#/$defs/iso_datetime" },
        "owner":          { "type": "string" },
        "repo_slug":      { "type": "string" },
        "repo_url":       { "type": "string" },
        "default_branch": { "type": "string" },
        "sha":            { "$ref": "#/$defs/sha40" },
        "short_sha":      { "type": "string", "minLength": 7, "maxLength": 7 },
        "committed_at":   { "type": ["string", "null"] },
        "author_name":    { "type": ["string", "null"] },
        "author_email":   { "type": ["string", "null"] },
        "message":        { "type": "string", "description": "First line of commit message only" },
        "files_changed":  { "type": "integer", "minimum": 0 }
      }
    }
  }
}
```

---

## Sentry Logic — Step-by-Step Algorithm

This runs at the **start** of `github-catalog-datafetcher.sh`, before any bare clone or file traversal.

```
INPUT:  REPO_URL, REPO_SLUG, BRANCH, CATALOG_JSONL, LOG_FILE

STEP 1 — Resolve remote HEAD SHA (cheap, no clone)
  cmd="git ls-remote $REPO_URL refs/heads/$BRANCH"
  log_cmd "$cmd"
  REMOTE_SHA=$(git ls-remote "$REPO_URL" "refs/heads/$BRANCH" 2>>"$LOG_FILE" \
               | awk '{print $1}')
  GIT_EXIT=$?
  log_result "$cmd" "$GIT_EXIT" "sha=$REMOTE_SHA"

STEP 2 — Guard: if git ls-remote failed
  if [[ $GIT_EXIT -ne 0 || -z "$REMOTE_SHA" ]]; then
    log_error "UNREACHABLE repo=$REPO_SLUG url=$REPO_URL"
    write_error_record   # collection_skipped=false, errors=["unreachable"]
    exit 1
  fi

STEP 3 — Query last known SHA from JSONL with jq
  if [[ -f "$CATALOG_JSONL" ]]; then
    LAST_SHA=$(jq -rn --arg slug "$REPO_SLUG" \
      '[inputs | select(.record_type=="repo_snapshot" and .repo_slug==$slug)]
       | last | .head_commit_sha // empty' \
      "$CATALOG_JSONL" 2>/dev/null)
  else
    LAST_SHA=""
  fi
  log_info "sentry slug=$REPO_SLUG remote=$REMOTE_SHA last=$LAST_SHA"

STEP 4 — Compare
  if [[ -n "$LAST_SHA" && "$REMOTE_SHA" == "$LAST_SHA" ]]; then
    log_info "SKIP repo=$REPO_SLUG sha_unchanged=$REMOTE_SHA"
    write_skip_record    # collection_skipped=true, all catalog fields null/empty
    exit 0
  fi

STEP 5 — Proceed with full collection
  log_info "COLLECT repo=$REPO_SLUG old=$LAST_SHA new=$REMOTE_SHA"
  # ... bare clone, ls-tree, semantic extraction, commit harvesting ...
```

> **jq note:** The `inputs` builtin with `-n` flag reads every line of the JSONL file as a separate JSON value, enabling correct streaming over multi-record files without loading a JSON array. This is the only correct way to query JSONL with jq.

---

## Script Architecture

### `github-catalog-orchestrator.sh`

**Responsibilities:** Resolve repo list → dispatch datafetcher workers in parallel batches → enforce 1-second inter-dispatch delay → render live progress bar → drain workers → write run summary to log.

**Inputs:**
- `--owner NAME` — git host owner
- `--repos GLOB` — shell glob for filtering (e.g. `ados-*`, `*`)
- `--type private|public|all` — recorded in snapshot `filter` field
- `--parallel N` — max concurrent workers (default: 4)
- `--repo-list-file PATH` — newline-separated slugs; skips remote discovery
- `--data-dir DIR` — JSONL output dir (default: `data/`)
- `--log-dir DIR` — log file dir (default: `logs/`)
- `--report-id ID` — shared run timestamp (defaults to `date -u +%Y-%m-%dT%H:%M:%SZ`)
- `--limit N` — cap matched repos (0 = no cap; for smoke runs)

**Key Bash patterns:**

```bash
# --- Progress bar (writes to stderr/terminal, never to log file) ---
progress_bar() {
  local current=$1 total=$2 label=$3
  local width=24
  local filled=$(( total > 0 ? current * width / total : 0 ))
  local empty=$(( width - filled ))
  local bar
  bar="$(printf '%0.s#' $(seq 1 $filled))$(printf '%0.s.' $(seq 1 $empty))"
  printf '\r\033[K\033[1m[%s]\033[0m %d/%d  %s' \
    "$bar" "$current" "$total" "$label" >&2
}

# --- Log function (writes to LOG_FILE only, never stdout/stderr) ---
log() {
  local level="$1"; shift
  printf '%s [%s] %s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$level" "$*" >> "$LOG_FILE"
}
log_cmd()    { log CMD  "$*"; }
log_info()   { log INFO "$*"; }
log_error()  { log ERROR "$*"; }

# --- Parallel dispatch loop with 1-second inter-dispatch delay ---
running=0
completed=0
failures=0
total=${#REPOS[@]}

for repo in "${REPOS[@]}"; do
  log_info "DISPATCH repo=$repo running=$running parallel=$PARALLEL"
  progress_bar "$completed" "$total" "dispatching → $repo"

  "$FETCHER" \
    --owner   "$OWNER" \
    --repo    "$repo" \
    --type    "$VISIBILITY" \
    --report-id "$REPORT_ID" \
    --data-dir  "$DATA_DIR" \
    --log-file  "$LOG_FILE" \
    2>>"$LOG_FILE" &

  (( running++ ))
  sleep 1                              # mandatory 1-second inter-dispatch delay

  # Drain one slot if at capacity
  while (( running >= PARALLEL )); do
    if wait -n; then                   # Bash 5.0+: wait for any one child
      log_info "WORKER_OK slot_freed"
    else
      (( failures++ ))
      log_error "WORKER_FAIL exit=$?"
    fi
    (( running-- ))
    (( completed++ ))
    progress_bar "$completed" "$total" "running $running workers"
  done
done

# --- Drain phase: wait for all remaining workers ---
while (( running > 0 )); do
  if wait -n; then
    log_info "DRAIN_OK"
  else
    (( failures++ ))
    log_error "DRAIN_FAIL exit=$?"
  fi
  (( running-- ))
  (( completed++ ))
  progress_bar "$completed" "$total" "draining ($running left)"
done

printf '\n' >&2   # final newline after progress bar

log_info "RUN_DONE report_id=$REPORT_ID completed=$completed failures=$failures"
(( failures == 0 )) || { printf 'FAILED: %d worker(s) failed. See %s\n' "$failures" "$LOG_FILE" >&2; exit 1; }
```

---

### `github-catalog-datafetcher.sh`

**Responsibilities:** Sentry check → bare-clone into temp dir → `git ls-tree` for key-file detection → `git show HEAD:README.md` + `awk`/`sed` for semantic extraction → `git log` for commit harvest → assemble JSONL record → atomic append.

**Key patterns:**

```bash
# --- Bare clone into temp dir (no working tree, fast) ---
TMP_CLONE="$(mktemp -d)"
trap 'rm -rf "$TMP_CLONE"' EXIT

cmd="git clone --bare --depth 50 --single-branch --branch $BRANCH $REPO_URL $TMP_CLONE"
log_cmd "$cmd"
t0=$(date +%s%N)
git clone --bare --depth 50 --single-branch \
  --branch "$BRANCH" "$REPO_URL" "$TMP_CLONE" 2>>"$LOG_FILE"
git_exit=$?
elapsed=$(( ($(date +%s%N) - t0) / 1000000 ))
log_cmd "RESULT exit=$git_exit elapsed_ms=$elapsed"
(( git_exit == 0 )) || { log_error "clone_failed repo=$REPO_SLUG"; write_error_record; exit 1; }

# --- Key-file detection via git ls-tree ---
KEY_FILES_SENTINEL=("README.md" "PROJECT.md" "INSTALL.md" "GOALS.md" \
  "REQUIREMENTS.md" "APP-REQS.md" "Makefile" ".github/workflows" \
  "Dockerfile" "package.json" "go.mod" "Cargo.toml" "pyproject.toml")

key_files_json="[]"
for f in "${KEY_FILES_SENTINEL[@]}"; do
  if git --git-dir="$TMP_CLONE" ls-tree HEAD --name-only "$f" 2>/dev/null | grep -q .; then
    key_files_json=$(printf '%s' "$key_files_json" | jq --arg f "$f" '. + [$f]')
  fi
done

# --- Semantic extraction from README via awk (heading → next heading) ---
extract_section() {
  local heading_pattern="$1"       # e.g. "^## GOAL$" or "^### GOAL$"
  local file_content="$2"          # raw content piped in
  printf '%s\n' "$file_content" | awk \
    -v pat="$heading_pattern" \
    'p && /^#{1,4} / { exit }
     /^#{1,4} / && $0 ~ pat { p=1; next }
     p { print }'
}

readme_content=$(git --git-dir="$TMP_CLONE" show "HEAD:README.md" 2>/dev/null || true)
goal_text=$(extract_section "GOAL" "$readme_content" | sed '/^[[:space:]]*$/d' | head -20)
# ... repeat for objectives, flows, requirements

# --- jq assembly of the final record ---
RECORD=$(jq -nc \
  --arg sv    "1.0.0" \
  --arg rid   "$REPORT_ID" \
  --arg gat   "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --argjson cs false \
  --arg own   "$OWNER" \
  --arg slug  "$REPO_SLUG" \
  --arg url   "$REPO_URL" \
  --arg br    "$BRANCH" \
  --arg sha   "$HEAD_SHA" \
  --arg sha_t "$HEAD_COMMIT_AT" \
  --arg desc  "$GIT_DESCRIPTION" \
  --arg cr    "$CREATED_AT" \
  --argjson kf  "$key_files_json" \
  --argjson goal_obj  "$GOAL_OBJ" \
  --argjson obj_obj   "$OBJ_OBJ" \
  --argjson flow_obj  "$FLOW_OBJ" \
  --argjson req_obj   "$REQ_OBJ" \
  --argjson errors    "[]" \
  '{
    schema_version: $sv,
    record_type: "repo_snapshot",
    report_id: $rid,
    generated_at: $gat,
    collection_skipped: $cs,
    owner: $own,
    repo_slug: $slug,
    repo_url: $url,
    default_branch: $br,
    head_commit_sha: $sha,
    head_commit_at: $sha_t,
    git_description: $desc,
    created_at: $cr,
    key_files_present: $kf,
    goal: $goal_obj,
    objectives: $obj_obj,
    flows: $flow_obj,
    requirements: $req_obj,
    errors: $errors
  }')

# --- Atomic JSONL append with flock ---
LOCK_FILE="$DATA_DIR/.catalog.lock"
(
  flock -x 200
  printf '%s\n' "$RECORD" >> "$CATALOG_JSONL"
) 200>"$LOCK_FILE"
```

---

### `github-catalog-report.sh`

**Responsibilities:** Read both JSONL files using `jq` only → aggregate stats → render structured Markdown. Zero network/git calls.

```bash
# --- Summary table: latest non-skipped snapshot per repo ---
jq -rn --arg catalog "$CATALOG_JSONL" '
  [inputs | select(.record_type == "repo_snapshot")]
  | group_by(.repo_slug)
  | map(
      sort_by(.generated_at) | last
      | {
          slug:   .repo_slug,
          sha:    (.head_commit_sha[:7]),
          at:     .head_commit_at,
          files:  (.key_files_present | length),
          goal:   (.goal.text // "—" | split("\n")[0] | .[0:80]),
          skipped: .collection_skipped
        }
    )
  | sort_by(.slug)
  | ["| Repo | SHA | Last Commit | Key Files | Goal (excerpt) |",
     "|------|-----|-------------|-----------|----------------|"]
    + map("| \(.slug) | `\(.sha)` | \(.at // "—") | \(.files) | \(.goal) |")
  | .[]
' "$CATALOG_JSONL"

# --- Commit activity summary per repo ---
jq -rn '
  [inputs | select(.record_type == "commit")]
  | group_by(.repo_slug)
  | map({
      repo:   .[0].repo_slug,
      count:  length,
      latest: (sort_by(.committed_at) | last | .committed_at)
    })
  | sort_by(.repo)
  | .[]
  | "| \(.repo) | \(.count) | \(.latest) |"
' "$COMMITS_JSONL"
```

---

## Implementation Steps

Each step names the file to create and states its acceptance test.

| # | File | Action | Acceptance Test |
|---|---|---|---|
| 1 | `.gitignore` | Add ignore rules for `data/`, `reports/`, `logs/`, `.cache/` | `git status` shows only tracked files after running scripts |
| 2 | `docs/github-catalog.schema.json` | Write the full JSON Schema from this ADR | `jq '.' docs/github-catalog.schema.json` exits 0 |
| 3 | `scripts/github-catalog-datafetcher.sh` | Skeleton: arg parsing + `usage()` + `log()` + `fail()` helpers only | `bash -n scripts/github-catalog-datafetcher.sh` exits 0 |
| 4 | `scripts/github-catalog-datafetcher.sh` | Add Sentry Logic (Steps 1–4 from algorithm above) | Run against unreachable fake URL: exits 1 with error record in JSONL |
| 5 | `scripts/github-catalog-datafetcher.sh` | Add bare clone + `git ls-tree` key-file detection | Against a local bare test repo: `key_files_present` array is non-empty |
| 6 | `scripts/github-catalog-datafetcher.sh` | Add `awk`/`sed` semantic extraction for goal/objectives/flows/requirements | Extract from a README fixture: `goal.text` is non-empty |
| 7 | `scripts/github-catalog-datafetcher.sh` | Add `git log` commit harvesting + `flock` append to `git-projects-commits.jsonl` | Commit lines appear in JSONL; `jq -c '.' < git-projects-commits.jsonl` parses every line |
| 8 | `scripts/github-catalog-datafetcher.sh` | Add `jq -nc` record assembly + `flock` append to `git-projects-catalog.jsonl` | Snapshot line appears in JSONL; passes schema validation with `jq` filter |
| 9 | `scripts/github-catalog-orchestrator.sh` | Skeleton: arg parsing + repo-list-file reader + log/progress helpers | `bash -n` exits 0; `--help` prints usage |
| 10 | `scripts/github-catalog-orchestrator.sh` | Add parallel dispatch loop with `sleep 1` + `wait -n` drain | Running with `--parallel 2 --limit 3` against local repos: progress bar visible, exits 0 |
| 11 | `scripts/github-catalog-orchestrator.sh` | Add run-summary record written to `git-projects-catalog.jsonl` after drain | JSONL contains one `record_type="run"` line per orchestrator invocation |
| 12 | `scripts/github-catalog-report.sh` | Pure-jq markdown generator: summary table + commit stats + per-repo sections | Running against fixture JSONL produces non-empty `.md`; no network calls |
| 13 | All scripts | Add `LC_ALL=C` guards around `awk`/`sed` text extraction to handle non-UTF-8 | No garbled output when a repo file contains high-byte characters |
| 14 | `tests/smoke-test.sh` | Offline smoke: create local bare repo → run datafetcher → run twice → check skip | Second run writes `collection_skipped: true`; both JSONL lines parse with `jq` |
| 15 | `tests/smoke-test.sh` | Report smoke: run `github-catalog-report.sh` against fixture JSONL → assert non-empty | `wc -l reports/latest.md` returns > 10 |

---

## Testing Strategy

### 1. Syntax check (zero-cost, must always pass)

```bash
bash -n scripts/github-catalog-orchestrator.sh
bash -n scripts/github-catalog-datafetcher.sh
bash -n scripts/github-catalog-report.sh
```

### 2. Offline smoke test (no network required)

```bash
#!/usr/bin/env bash
# tests/smoke-test.sh

set -euo pipefail
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Create a local bare git repo to simulate a remote
BARE="$WORK/fake-remote.git"
git init --bare "$BARE"

# Seed it with one commit
SEED="$(mktemp -d)"
trap 'rm -rf "$SEED"' EXIT INT TERM
git -C "$SEED" init
git -C "$SEED" config user.email "test@test.com"
git -C "$SEED" config user.name "Test"
cat > "$SEED/README.md" <<'MD'
# Fake Project

## GOAL
Test the sentry and collection logic.

## OBJECTIVES
1. Write a JSONL line
2. Skip on re-run
MD
git -C "$SEED" add .
git -C "$SEED" commit -m "init"
git -C "$SEED" remote add origin "$BARE"
git -C "$SEED" push origin main

DATA_DIR="$WORK/data"
mkdir -p "$DATA_DIR"

# --- First run: should collect ---
./scripts/github-catalog-datafetcher.sh \
  --owner "testowner" \
  --repo  "fake-remote" \
  --repo-url "file://$BARE" \
  --branch "main" \
  --type  "private" \
  --report-id "2026-06-17T00:00:00Z" \
  --data-dir "$DATA_DIR"

CATALOG="$DATA_DIR/git-projects-catalog.jsonl"
[[ -f "$CATALOG" ]] || { echo "FAIL: catalog not written"; exit 1; }

# Every line must parse
jq -c '.' < "$CATALOG" > /dev/null || { echo "FAIL: invalid JSONL"; exit 1; }

SKIPPED_1=$(jq -r '.collection_skipped' < <(tail -1 "$CATALOG"))
[[ "$SKIPPED_1" == "false" ]] || { echo "FAIL: first run must not skip"; exit 1; }

# --- Second run: same HEAD → must skip ---
./scripts/github-catalog-datafetcher.sh \
  --owner "testowner" \
  --repo  "fake-remote" \
  --repo-url "file://$BARE" \
  --branch "main" \
  --type  "private" \
  --report-id "2026-06-17T00:00:01Z" \
  --data-dir "$DATA_DIR"

SKIPPED_2=$(jq -r '.collection_skipped' < <(tail -1 "$CATALOG"))
[[ "$SKIPPED_2" == "true" ]] || { echo "FAIL: second run must skip (same SHA)"; exit 1; }

echo "PASS: sentry logic OK"
```

### 3. JSONL integrity check

```bash
# Run after any datafetcher invocation — every line in both files must parse
jq -c '.' < data/git-projects-catalog.jsonl  > /dev/null && echo "catalog OK"
jq -c '.' < data/git-projects-commits.jsonl  > /dev/null && echo "commits OK"
```

### 4. Report smoke test

```bash
./scripts/github-catalog-report.sh \
  --catalog data/git-projects-catalog.jsonl \
  --commits data/git-projects-commits.jsonl \
  --output  /tmp/test-report.md

[[ $(wc -l < /tmp/test-report.md) -gt 10 ]] && echo "PASS: report non-empty"
```

### 5. Deduplication check for commits

```bash
# No (repo_slug, sha) pair should appear more than once
jq -rn '[inputs | select(.record_type=="commit") | "\(.repo_slug)|\(.sha)"] | group_by(.) | map(select(length > 1)) | length' \
  data/git-projects-commits.jsonl \
  | grep -q '^0$' && echo "PASS: no duplicate commits"
```

---

## Architecture Diagram

---

## Summary

**WSL environment:** Linux 6.6.114.1-microsoft-standard-WSL2 · jq-1.7 — both confirmed available.

The ADR specifies a complete from-scratch rewrite with these key decisions:

| Decision | Rationale |
|---|---|
| `git ls-remote` for sentry check | Zero-cost HEAD resolution without cloning; works on any git remote |
| `jq -rn '[inputs \| ...]'` for JSONL reads | Correct streaming over multi-record JSONL; jq-native, no shell loops |
| `flock -x` for JSONL appends | Safe concurrent writes from parallel worker subshells |
| `git clone --bare --depth 50` | Minimal clone for file inspection; temp dir cleaned via `trap EXIT` |
| `wait -n` drain loop (Bash 5.0+) | Native parallel job management without external tools |
| Two separate JSONL files | Commits and snapshots have different access patterns; LLM agents query each independently |

**Next step:** Begin with Step 1 (`.gitignore`) through Step 3 (script skeleton + syntax check) to establish the file structure, then iterate through the Sentry Logic in Step 4 against a local bare-repo fixture before touching any live remote.