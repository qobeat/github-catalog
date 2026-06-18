# github-catalog

Standalone Bash/jq/git tool for building an append-only catalog of git repositories without cloning full working trees and without LLM summarization.

This repository implements the rewrite described in [docs/ADR-001-github-catalog-rewrite.md](docs/ADR-001-github-catalog-rewrite.md): three Bash scripts, JSON Schema, append-only JSONL streams, pure-Bash tests, and offline smoke tests.

## Prerequisites

- Bash 5.0+ (for `wait -n` in the orchestrator)
- `jq` 1.7+
- `git`
- `shellcheck` (optional, for local linting)

Repo discovery uses `--repo-list-file` (pure Bash). The orchestrator does not call the GitHub API or `gh`.

## Repository layout

Tracked files:

| Path | Role |
| --- | --- |
| `README.md` | This file |
| `docs/ADR-001-github-catalog-rewrite.md` | Architecture decision record: schemas, sentry algorithm, script design, acceptance tests |
| `docs/github-catalog.schema.json` | JSON Schema for `repo_snapshot`, `commit`, and `run` JSONL records |
| `scripts/github-catalog-orchestrator.sh` | Parallel dispatcher with progress bar and run summary |
| `scripts/github-catalog-datafetcher.sh` | Single-repo sentry check, collection, and JSONL append |
| `scripts/github-catalog-report.sh` | Pure-`jq` Markdown report generator |
| `tests/lint.sh` | Pure-Bash syntax and ShellCheck runner |
| `tests/test.sh` | Pure-Bash unit test runner (also invokes smoke tests) |
| `tests/smoke-test.sh` | Offline integration tests for sentry skip and report generation |
| `tests/test_*.sh` | Unit tests for extraction, orchestrator helpers, and schema validation |
| `tests/MANIFEST.md` | AI agent instructions for testing protocols |
| `.gitignore` | Ignores generated `data/`, `reports/`, `logs/`, and `.cache/` |

Generated at runtime (gitignored):

| Path | Role |
| --- | --- |
| `data/git-projects-catalog.jsonl` | Append-only repository snapshot history |
| `data/git-projects-commits.jsonl` | Append-only commit records |
| `reports/latest.md` | Generated Markdown report |
| `logs/github-catalog-YYYY-MM-DD.log` | Timestamped structured run log |
| `.cache/` | Rebuildable cache and temporary worker state |

## JSONL schema

Each line in the JSONL files is one JSON object. Record types:

- **`repo_snapshot`** — repository identity, HEAD SHA, key files, and verbatim semantic fields (`goal`, `objectives`, `flows`, `requirements`) extracted from README headings
- **`commit`** — individual commit metadata, deduplicated on `(repo_slug, sha)`  
- **`run`** — orchestrator run summary (one line appended per orchestrator invocation)

Full field definitions and examples are in the ADR and in `docs/github-catalog.schema.json`.

Validate the schema file:

```bash
jq '.' docs/github-catalog.schema.json
```

## Scripts

### `scripts/github-catalog-orchestrator.sh`

Dispatches one datafetcher worker per matched repository with a live progress bar, 1-second inter-dispatch delay, `wait -n` concurrency control, and a `run` summary record appended to the catalog JSONL.

```bash
scripts/github-catalog-orchestrator.sh --help
```

| Flag | Meaning |
| --- | --- |
| `--user`, `--owner` | Git host owner; URL forms like `https://github.com/qobeat` are accepted |
| `--repos` | Repository glob, e.g. `*` or `ados-*` |
| `--type` | `private`, `public`, or `all` (recorded in run summary) |
| `--repo-list-file` | **Required.** Newline-separated slugs; optional URL and branch per line |
| `--parallel` | Max concurrent workers (default: 4) |
| `--limit` | Cap matched repositories (0 = no cap) |
| `--data-dir` | JSONL output directory (default: `data/`) |
| `--log-dir` | Log file directory (default: `logs/`) |
| `--report-id` | UTC run id (default: current timestamp) |
| `--fetcher` | Path to datafetcher script |

Repo list file format:

```
slug
slug  git@github.com:owner/slug.git
slug  file:///path/to/repo.git  main
```

### `scripts/github-catalog-datafetcher.sh`

Performs sentry checks (`git ls-remote`), bare clone, semantic extraction, commit harvesting, and flock-protected JSONL append for one repository.

```bash
scripts/github-catalog-datafetcher.sh --help
```

| Flag | Meaning |
| --- | --- |
| `--owner`, `--user` | Git host owner or organization |
| `--repo` | Repository short name (no `owner/` prefix) |
| `--type` | `private`, `public`, or `all` (required; visibility is recorded in orchestrator `run` records) |
| `--report-id` | UTC run id shared with the orchestrator |
| `--repo-url` | Clone URL (SSH, HTTPS, or `file://`); default: `git@github.com:OWNER/REPO.git` |
| `--branch` | Default branch (default: `main`) |
| `--data-dir` | JSONL output directory (default: `data/`) |
| `--log-file` | Log file path (default: `logs/github-catalog-YYYY-MM-DD.log`) |

### `scripts/github-catalog-report.sh`

Generates a Markdown report from catalog and commit JSONL files using `jq` only (no git or network calls).

```bash
scripts/github-catalog-report.sh --help
```

| Flag | Meaning |
| --- | --- |
| `--catalog` | Catalog JSONL path (default: `data/git-projects-catalog.jsonl`) |
| `--commits` | Commits JSONL path (default: `data/git-projects-commits.jsonl`) |
| `--output` | Output Markdown file (default: `reports/latest.md`) |

## Testing and Linting

This project strictly avoids external testing frameworks (no Python, no BATS) to maintain maximum portability. All testing is handled natively via Bash.

**1. Run linters (syntax and ShellCheck)**

```bash
./tests/lint.sh
```

**2. Run unit and smoke tests**

```bash
./tests/test.sh
```

This runs `bash -n` on all scripts, discovers and executes every `test_*.sh` file, then runs `./tests/smoke-test.sh` for offline integration coverage.

**3. Run smoke tests only**

```bash
./tests/smoke-test.sh
```

**4. Manual syntax check**

```bash
bash -n scripts/github-catalog-orchestrator.sh
```

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
