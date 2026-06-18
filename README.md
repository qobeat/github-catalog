# github-catalog

Standalone Bash/jq/git tool for building an append-only catalog of git repositories without cloning full working trees and without LLM summarization.

This repository implements the rewrite described in [docs/ADR-001-github-catalog-rewrite.md](docs/ADR-001-github-catalog-rewrite.md). 

## Prerequisites

- Bash 5.0+ (for `wait -n` in the orchestrator)
- `jq` 1.7+
- `git`
- `gh` (Optional: Only required if generating repo lists via `--refresh-repo-list`)
- `shellcheck` (Optional: For local linting)

## Repository layout

Tracked files:

| Path | Role |
| --- | --- |
| `README.md` | This file |
| `docs/ADR-001-github-catalog-rewrite.md` | Architecture decision record: schemas, sentry algorithm, script design |
| `docs/github-catalog.schema.json` | JSON Schema for catalog records |
| `scripts/qobeat-repos.sh` | Convenience wrapper for `qobeat` user execution |
| `scripts/github-catalog-orchestrator.sh` | Parallel dispatcher with progress bar and run summary |
| `scripts/github-catalog-datafetcher.sh` | Single-repo sentry check, collection, and JSONL append |
| `scripts/github-gh.sh` | Isolated `gh` API interface for repo discovery |
| `tests/lint.sh` | Pure-Bash syntax and ShellCheck runner |
| `tests/test.sh` | Pure-Bash zero-dependency unit test runner |
| `MANIFEST.md` | AI Agent instructions for repository interaction |

Generated at runtime (gitignored):

| Path | Role |
| --- | --- |
| `data/<user-name>/user-repositories.jsonl` | Append-only inventory of discovered repositories |
| `data/<user-name>/git-projects-catalog.jsonl` | Append-only repository snapshot history |
| `data/<user-name>/git-projects-commits.jsonl` | Append-only commit records |
| `logs/github-catalog-YYYY-MM-DD.log` | Timestamped structured run log |

## User Wrapper

To scan `qobeat` repositories, the easiest method is to use the dedicated wrapper which handles owner assignment automatically:

```bash
./scripts/qobeat-repos.sh '*' --type private --refresh-repo-list

```

The first argument must be the repository mask (glob). All subsequent arguments are passed to the orchestrator.

## Scripts

### `scripts/github-catalog-orchestrator.sh`

Dispatches one datafetcher worker per matched repository with a live progress bar.

```bash
scripts/github-catalog-orchestrator.sh --help

```

| Flag | Meaning |
| --- | --- |
| `--user`, `--owner` | Git host owner; URL forms like `https://github.com/qobeat` are accepted |
| `--repos` | Repository glob, e.g. `*` or `ados-*` |
| `--type` | `private`, `public`, or `all` |
| `--refresh-repo-list` | If passed, calls `github-gh.sh` to update `user-repositories.jsonl` |
| `--parallel` | Max concurrent workers (default: 4) |
| `--data-dir` | Output directory (defaults to `data/<user-name>/`) |

### `scripts/github-gh.sh`

Isolates all non-standard GitHub platform dependencies. It invokes `gh repo list` and streams the results into `user_repository` JSONL format.

```bash
scripts/github-gh.sh list-repos --owner qobeat --type private --report-id 123 --data-dir data/qobeat/

```

### `scripts/github-catalog-datafetcher.sh`

Performs sentry checks (`git ls-remote`), bare clone, semantic extraction, commit harvesting, and flock-protected JSONL append for one repository.

## Testing and Linting

This project strictly avoids external testing frameworks (no Python, no BATS).

**1. Run Linters (Syntax & Shellcheck)**

```bash
./tests/lint.sh

```

**2. Run Unit Tests**

```bash
./tests/test.sh

```
