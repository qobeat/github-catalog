# AI Agent Scripts Manifest: Execution Guide

**ATTENTION LLM / AGENT:** This document dictates how to execute the `github-catalog` pipeline to discover, fetch, and report on git repositories.

## The Standard Execution Pipeline

To generate a catalog and report, you must run the scripts in the following sequence. Do not call `github-catalog-datafetcher.sh` directly unless debugging a single repository.

### Primary Interface: The Wrapper
If targeting the `qobeat` user, ALWAYS use the wrapper script. It mandates a repository mask (glob) and automatically forwards all trailing arguments to the orchestrator.

```bash
./scripts/qobeat-repos.sh '*' --type private --refresh-repo-list --parallel 4

```

### Understanding the Flags

* `--refresh-repo-list`: Triggers `github-gh.sh` to update the inventory file (`data/<owner>/user-repositories.jsonl`) via the `gh` API before starting collection. If omitted, the orchestrator relies on the existing local JSONL inventory.
* `--type private|public|all`: Filters the collection run.

### Data Flow

1. **Inventory Generation:** `github-gh.sh` writes schema-compliant `user_repository` records.
2. **Collection:** The orchestrator dispatches the fetcher. Unchanged repos skip execution via `git ls-remote`.
3. **Storage:** Snapshots append to `data/<owner>/git-projects-catalog.jsonl`. Commits append to `data/<owner>/git-projects-commits.jsonl`.

## Constraints

* Always execute scripts from the repository root, not from inside the `scripts/` directory.
* Never manually edit the output JSONL files.

