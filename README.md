# My Unix Scripts

Small CLI toolbox for WSL, Ubuntu, and other Linux environments.

This repository is the source of truth for scripts actually used on the workstation. The install flow puts selected commands in a bin directory on `PATH`, while keeping shared Bash helpers, legacy imports, generated data, and project-maintenance scripts in the repository.

## Quickstart

Use `~/.local/bin` as the default install location.

```bash
git clone git@github.com:<YOUR_USER>/my-unix-scripts.git
cd my-unix-scripts
mkdir -p "$HOME/.local/bin"
./scripts/install.sh --mode symlink --bin-dir "$HOME/.local/bin"
```

If `~/.local/bin` is not already on `PATH`:

```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

After install, commands such as `git-alias`, `ollama-gen`, and `ollama-perf` are available from `~/.local/bin/`.

## Installation

The installer scans top-level shebang-based commands in `scripts/` and installs them into the chosen bin directory.

- `symlink` mode is best while developing in this repo. Changes in `scripts/` are live immediately.
- `copy` mode is best for a stable install or a second machine.
- `~/.local/bin` is the recommended target bin directory.
- `~/bin` also works if that is already part of the local shell setup.

Common install commands:

```bash
./scripts/install.sh --mode symlink --bin-dir "$HOME/.local/bin"
./scripts/install.sh --mode copy --bin-dir "$HOME/.local/bin" --force
./scripts/install.sh --add <name>
./scripts/install.sh --list
./scripts/uninstall.sh
./scripts/uninstall.sh --purge-data
```

See `INSTALL.md` for full install, update, uninstall, and multi-machine setup details.

## Command Catalog

These commands are installed into your bin directory by `./scripts/install.sh`:

| Command | Purpose |
| --- | --- |
| `unzip-gpt.sh` | Safely update a repository from GPT zip. |
| `git-alias` | Inspect, search, expand, add, and remove global Git aliases. |
| `ollama-gen` | Simple wrapper around Ollama `/api/generate`, with JSON output support. |
| `ollama-perf` | Run a local Ollama performance and health benchmark, producing log and CSV output. |
| `ollama-perf-table` | Render benchmark CSV data as a readable terminal report. |
| `calc_perf_ollama.py` | Summarize an Ollama benchmark CSV as JSON statistics. |
| `calc_perf_ollama_table.py` | Format benchmark CSV data into a compact text table. |
| `zip_ignore.sh` | Zip a directory while applying gitignore-like exclusion rules. |
| `zip_git_ignore.sh` | Zip tracked and untracked, non-ignored files from a Git working tree. |
| `ados_verify_claims.py` | Validate ADOS JSON files against the local git repo; optional Gemini claim check. |
| `extract_claims.py` | Extract architectural claims from repo files via Gemini and write repo_files.json and repo_claims_journal.json. |
| `test_gemini_connection.py` | Verify GEMINI_API_KEY and list available Gemini models. |
| `convert_sources_to_md.py` | Convert all source documents in a folder into one long Markdown file, preserving paths. |

## Repo Maintenance Helpers

These are project-management scripts kept in the repo and run as `./scripts/...`; they are not installed as regular user commands:

- `./scripts/install.sh` installs repo commands into `~/.local/bin`, `~/bin`, or another bin directory. Use `--add <name>` to run lint, then install.
- `./scripts/uninstall.sh` removes installed commands by reading the manifest created during install.
- `./scripts/lint.sh` runs shell lint/format checks for shell sources.
- `./scripts/lint-python.sh` compiles Python catalog modules and runs Python unit tests when tests exist.
- `./scripts/ci-local.sh` runs the same checks as GitHub CI.
- `./scripts/import-bin.sh` imports a `bin.zip` archive into `legacy/bin/` for cleanup and refactoring.

---

## GitHub Catalog Tool

### GOAL

Create a repeatable, local-first, append-only catalog of GitHub repositories for a selected GitHub owner, so the repository set can be audited over time by identity, metadata, self-declared project semantics, structure, inventory metrics, execution flows, and change history without cloning repositories and without using LLM summarization.

### OBJECTIVES

| ID | Objective | Success condition |
| --- | --- | --- |
| GCAT-OBJ-001 | Collect repository identity and metadata for a GitHub owner using the authenticated GitHub CLI. | A run captures slug, URL, GitHub description, timestamps, default branch, visibility filter, and report id for every matched non-empty repository. |
| GCAT-OBJ-002 | Extract self-defined repository semantics deterministically. | Full name, description, GOAL, OBJECTIVES, and REQUIREMENTS are copied verbatim from repository files with source file and source heading annotations. |
| GCAT-OBJ-003 | Preserve history in append-only JSONL. | Each run appends one `repo_snapshot` line per repository and never rewrites prior snapshot lines. |
| GCAT-OBJ-004 | Avoid expensive collection when a repository has not changed. | When the default-branch HEAD is unchanged, the tool appends a skipped snapshot that reuses the last full snapshot and avoids heavy file/API fetches. |
| GCAT-OBJ-005 | Keep implementation portable. | Runtime uses Bash, Python standard library, and `gh`; no external Python packages and no repo clones are required. |
| GCAT-OBJ-006 | Keep private/generated data out of source control by default. | Generated JSONL, reports, and caches live under ignored data/cache/report folders. |

### REQUIREMENTS

| ID | Requirement | Verification |
| --- | --- | --- |
| GCAT-REQ-001 | The tool MUST support `--user`/`--owner`, `--repos` glob, `--type private\|public\|all`, `--parallel`, `--limit`, `--data-dir`, `--cache-dir`, and `--report-id`. | `scripts/github-catalog-orchestrator.sh --help` documents these flags; smoke test uses `--mock-catalog-json`. |
| GCAT-REQ-002 | The data fetcher MUST support single-repo collection and append exactly one JSON object per JSONL line. | `scripts/github-catalog-datafetcher.sh --mock-catalog-json ...` appends parseable JSONL. |
| GCAT-REQ-003 | The schema MUST define `run`, `repo_snapshot`, and `commit` records, with `repo_snapshot.repo.requirements` as a first-class extracted field. | `docs/github-catalog.schema.json` parses as valid JSON and documents all record types. |
| GCAT-REQ-004 | The extraction layer MUST preserve original wording and source identity. | Unit tests assert source file/heading fields for extracted semantic fields. |
| GCAT-REQ-005 | The tool MUST not substitute GitHub API `description` for GOAL, OBJECTIVES, or REQUIREMENTS. | Unit tests cover missing semantic fields and confirm they render as `not documented`. |
| GCAT-REQ-006 | The orchestrator MUST run multiple data fetchers in parallel and propagate non-zero worker failures. | Shell smoke test dispatches multiple mock repos with `--parallel 2`; failing worker returns non-zero exit. |
| GCAT-REQ-007 | Generated files MUST be excluded from normal source packaging/commits. | `.gitignore` and `.ignore` include `data/github-catalog/`, `reports/github-catalog/`, and `.cache/github-catalog/`. |
| GCAT-REQ-008 | The implementation MUST be runnable in a minimal Linux/WSL environment. | `bash -n scripts/github-catalog-*.sh`, `./scripts/lint-python.sh`, and mock datafetcher smoke test pass without network access. |

### Non-goals

- Do not clone repositories.
- Do not use LLM summarization or rewriting for cataloged fields.
- Do not add external Python packages such as `requests`, `pydantic`, or `jsonschema`.
- Do not commit generated private repository catalogs by default.
- Do not rename the existing Python collector unless all callers, tests, and docs are updated in the same change.

### Repository surfaces scanned

The collector should check these surfaces in priority order, preserving the first resolved value per bucket:

1. `PROJECT.md`, `PROJECT-INFO.md`, `PACKAGE.md`, `PACKAGE-INFO.md` at root and under `project/`
2. Matching `.json` and `.jsonl` variants
3. `GOV-REQS.md`, `ados/GOV-REQS.md`
4. `manifest.json`
5. `MANIFEST.md`
6. `README.md`
7. `GOAL.md`, `project/GOAL.md`
8. `APP-REQS.md`, `project/APP-REQS.md`
9. Root `.md` / `.txt` fallback for no-README repositories
10. GitHub API description only for the `github_description` field and last-resort `description`, never for GOAL/OBJECTIVES/REQUIREMENTS

Canonical semantic buckets:

| Bucket | Key | Accepted heading/key aliases |
| --- | --- | --- |
| Full name | `full_name` | full name, name, project name, package name, display name, title, README H1 |
| Description | `description` | description, purpose, about, overview, summary, product position, project scope |
| Goal | `goal` | goal, main goal, project goal, core goal, primary goal, north star, mission |
| Objectives | `objectives` | objectives, main objectives, project objectives, success criteria, key results |
| Requirements | `requirements` | requirements, app requirements, governance requirements, constraints, obligations, acceptance criteria |

### Files and folders

Tracked files:

| Path | Role |
| --- | --- |
| `README.md` | Human-facing project orientation and dedicated GitHub Catalog GOAL/OBJECTIVES/REQUIREMENTS. |
| `docs/github-catalog.schema.json` | JSON Schema for generated JSONL records and materialized catalog exports. |
| `scripts/github-catalog-orchestrator.sh` | Shell entrypoint for listing repos and dispatching parallel fetchers. |
| `scripts/github-catalog-datafetcher.sh` | Shell entrypoint for single-repo collection into JSONL. |
| `scripts/lint-python.sh` | Python compile/test runner for catalog modules and tests. |
| `scripts/catalog_qobeat_repos.py` | Existing Python collector; keep until a fully compatible generic collector replaces it. |

Generated local files, ignored by default:

| Path | Role |
| --- | --- |
| `data/github-catalog/catalog-snapshots.jsonl` | Append-only repository snapshot history. |
| `data/github-catalog/repo-commits.jsonl` | Append-only commit index/history. |
| `data/github-catalog/index.json` | Derived local index; rebuildable from JSONL. |
| `reports/github-catalog/latest.json` | Materialized latest-run JSON export. |
| `reports/github-catalog/latest.md` | Materialized latest-run Markdown report. |
| `reports/github-catalog/history/` | Per-repository history reports. |
| `.cache/github-catalog/` | API/file cache and temporary worker state. |

### Scripts

#### `github-catalog-orchestrator.sh`

Run several single-repo fetchers in parallel.

```bash
scripts/github-catalog-orchestrator.sh \
  --user qobeat \
  --repos 'ados-*' \
  --type private \
  --parallel 5 \
  --no-line-counts
```

Important flags:

| Flag | Meaning |
| --- | --- |
| `--user`, `--owner` | GitHub account/owner. URL forms like `https://github.com/qobeat` are accepted. |
| `--repos` | Repository glob, for example `*` or `ados-*`. |
| `--type` | `private`, `public`, or `all`. |
| `--parallel` | Number of concurrent datafetchers. |
| `--limit` | Maximum matched repositories for smoke runs. |
| `--data-dir` | Directory for append-only JSONL. Default: `data/github-catalog`. |
| `--cache-dir` | Cache directory. Default: `.cache/github-catalog`. |
| `--report-id` | UTC run id; defaults to current UTC timestamp. |
| `--repo-list-file` | Test/local mode: newline-separated repo slugs, no GitHub listing call. |
| `--mock-catalog-json` | Test/local mode: list repos and fetch snapshots from an existing catalog JSON file. |

#### `github-catalog-datafetcher.sh`

Fetch one repository and append a `repo_snapshot` JSONL line.

```bash
scripts/github-catalog-datafetcher.sh \
  --owner qobeat \
  --repo ados-greenlane \
  --type private \
  --report-id "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --data-dir data/github-catalog \
  --cache-dir .cache/github-catalog \
  --no-line-counts
```

Offline smoke mode using an existing catalog JSON file:

```bash
scripts/github-catalog-datafetcher.sh \
  --mock-catalog-json /path/to/qobeat-private-repos-smoke.json \
  --owner qobeat \
  --repo ados-apply-verify \
  --report-id 2026-06-17T00:00:00Z \
  --data-dir /tmp/github-catalog-data
```

### Testing

```bash
bash -n scripts/github-catalog-orchestrator.sh scripts/github-catalog-datafetcher.sh scripts/lint-python.sh
./scripts/lint-python.sh

# Offline smoke test, no gh required:
scripts/github-catalog-orchestrator.sh \
  --mock-catalog-json /path/to/qobeat-private-repos-smoke.json \
  --repos 'ados-*' \
  --type private \
  --parallel 2 \
  --limit 3 \
  --data-dir /tmp/github-catalog-data

python3 - <<'PY'
import json, pathlib
p = pathlib.Path('/tmp/github-catalog-data/catalog-snapshots.jsonl')
for line in p.read_text().splitlines():
    json.loads(line)
print('JSONL OK')
PY
```

### Ignore rules

Add these entries to `.gitignore`. Add the same entries to `.ignore` if this repository uses `.ignore` for packaging tools.

```gitignore
# GitHub Catalog generated private data
data/github-catalog/
reports/github-catalog/
.cache/github-catalog/

# Legacy qobeat catalog generated outputs
docs/qobeat-private-repos.json
docs/qobeat-private-repos.md
docs/qobeat-catalog/*.jsonl
docs/qobeat-catalog/index.json
```

## Typical Workflows

Install for active development:

```bash
./scripts/install.sh --mode symlink --bin-dir "$HOME/.local/bin"
```

Run repo lint locally before pushing:

```bash
./scripts/lint.sh
./scripts/lint-python.sh
```

Add a new installable script:

```bash
./scripts/install.sh --add git-alias
```

## Repo Layout

- `scripts/` contains installable commands plus repo-only maintenance helpers.
- `lib/` contains shared Bash helpers used by installed scripts.
- `legacy/` holds imported old scripts for reference and refactoring.
- `docs/` contains tracked documentation and schemas.
- `data/` contains local generated data and is ignored for private catalogs.
- `reports/` contains local generated reports and is ignored for private catalogs.
- `.cache/` contains rebuildable local cache data and is ignored.
