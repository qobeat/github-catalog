# github-catalog

Standalone Bash/jq/git tool for building an append-only catalog of git repositories without cloning full working trees and without LLM summarization.

This repository is an in-progress rewrite described in [docs/ADR-001-github-catalog-rewrite.md](docs/ADR-001-github-catalog-rewrite.md). The ADR defines the target architecture; several pieces are implemented, and core collection logic is still outstanding.

## Prerequisites

- Bash 5.0+ (for `wait -n` in the orchestrator)
- `jq` 1.7+
- `git`
- `python3` (used only by the orchestrator today for owner URL parsing and repo listing in live mode)

Live repo discovery in the orchestrator currently expects the GitHub CLI (`gh`) and a Python collector module that is **not** present in this repository. Offline workflows should use `--repo-list-file` once the datafetcher is complete.

## Repository layout

Tracked files:

| Path | Role |
| --- | --- |
| `README.md` | This file |
| `docs/ADR-001-github-catalog-rewrite.md` | Architecture decision record: schemas, sentry algorithm, script design, acceptance tests |
| `docs/github-catalog.schema.json` | JSON Schema for `repo_snapshot` and `commit` JSONL records |
| `scripts/github-catalog-orchestrator.sh` | Parallel dispatcher for per-repo datafetcher workers |
| `scripts/github-catalog-datafetcher.sh` | Single-repo collector (skeleton: arg parsing and logging helpers) |
| `scripts/lint-python.sh` | Local CI helper: `bash -n` on shell scripts; Python compile/test when present |
| `.gitignore` | Ignores generated `data/`, `reports/`, `logs/`, and `.cache/` |

Generated at runtime (gitignored):

| Path | Role |
| --- | --- |
| `data/git-projects-catalog.jsonl` | Append-only repository snapshot history |
| `data/git-projects-commits.jsonl` | Append-only commit records |
| `reports/latest.md` | Markdown report (planned; generator not yet present) |
| `logs/github-catalog-YYYY-MM-DD.log` | Timestamped structured run log |
| `.cache/` | Rebuildable cache and temporary worker state |

Not yet present (planned in ADR):

- `scripts/github-catalog-report.sh` — pure-`jq` Markdown report generator
- `tests/smoke-test.sh` — offline sentry and report smoke tests

## JSONL schema

Each line in the JSONL files is one JSON object. Record types:

- **`repo_snapshot`** — repository identity, HEAD SHA, key files, and verbatim semantic fields (`goal`, `objectives`, `flows`, `requirements`) extracted from README headings
- **`commit`** — individual commit metadata, deduplicated on `(repo_slug, sha)`

Full field definitions and examples are in the ADR and in `docs/github-catalog.schema.json`.

Validate the schema file:

```bash
jq '.' docs/github-catalog.schema.json
```

## Scripts

### `scripts/github-catalog-orchestrator.sh`

Dispatches one datafetcher worker per matched repository, with a concurrency cap via `wait -n`.

```bash
scripts/github-catalog-orchestrator.sh --help
```

Supported flags today:

| Flag | Meaning |
| --- | --- |
| `--user`, `--owner` | GitHub owner; URL forms like `https://github.com/qobeat` are accepted |
| `--repos` | Repository glob, e.g. `*` or `ados-*` |
| `--type` | `private`, `public`, or `all` |
| `--parallel` | Max concurrent workers (default: 5) |
| `--limit` | Cap matched repositories (0 = no cap) |
| `--data-dir` | JSONL output directory (default: `data/github-catalog`) |
| `--cache-dir` | Cache directory (default: `.cache/github-catalog`) |
| `--report-id` | UTC run id (default: current timestamp) |
| `--repo-list-file` | Newline-separated repo slugs; skips remote discovery |
| `--fetcher` | Path to datafetcher script |
| `--collector` | Path to Python collector (default: `scripts/catalog_qobeat_repos.py`, not shipped) |
| `--mock-catalog-json` | List repos from an existing catalog JSON file |
| `--no-line-counts`, `--delay-ms` | Passed through to the collector when used |

Example using a local repo list (no `gh` required for listing):

```bash
scripts/github-catalog-orchestrator.sh \
  --owner qobeat \
  --repos '*' \
  --type private \
  --parallel 2 \
  --limit 3 \
  --repo-list-file /path/to/repos.txt
```

**Note:** Default `--data-dir` is `data/github-catalog`, while the datafetcher defaults to `data/` and writes `git-projects-catalog.jsonl`. Align `--data-dir` explicitly until the orchestrator is updated to match the ADR layout.

### `scripts/github-catalog-datafetcher.sh`

Intended to perform sentry checks (`git ls-remote`), bare clone, semantic extraction, commit harvesting, and JSONL append for one repository. Currently implements argument parsing, structured logging to `--log-file`, and path defaults only.

```bash
scripts/github-catalog-datafetcher.sh --help
```

Supported flags today:

| Flag | Meaning |
| --- | --- |
| `--owner`, `--user` | Git host owner or organization |
| `--repo` | Repository short name (no `owner/` prefix) |
| `--type` | `private`, `public`, or `all` |
| `--report-id` | UTC run id shared with the orchestrator |
| `--repo-url` | Clone URL (SSH, HTTPS, or `file://`); default: `git@github.com:OWNER/REPO.git` |
| `--branch` | Default branch (default: `main`) |
| `--data-dir` | JSONL output directory (default: `data/`) |
| `--log-file` | Log file path (default: `logs/github-catalog-YYYY-MM-DD.log`) |

### `scripts/lint-python.sh`

Runs local checks appropriate for this repository:

```bash
./scripts/lint-python.sh
```

- `bash -n` on `scripts/github-catalog-orchestrator.sh`, `scripts/github-catalog-datafetcher.sh`, and itself
- `python3 -m py_compile` for any `scripts/*.py` or `tests/*.py` (none currently)
- `python3 -m unittest discover` when `tests/test_*.py` exists (none currently)

## Testing

Syntax and lint (always applicable):

```bash
bash -n scripts/github-catalog-orchestrator.sh scripts/github-catalog-datafetcher.sh
jq '.' docs/github-catalog.schema.json
./scripts/lint-python.sh
```

Offline smoke tests described in the ADR (`tests/smoke-test.sh`, report generation) are not yet implemented.

## Ignore rules

`.gitignore` excludes generated output:

```gitignore
data/
reports/
logs/
.cache/
```

## Further reading

See [docs/ADR-001-github-catalog-rewrite.md](docs/ADR-001-github-catalog-rewrite.md) for the full target design: sentry algorithm, parallel dispatch with progress feedback, semantic extraction patterns, commit deduplication, and step-by-step acceptance criteria.
