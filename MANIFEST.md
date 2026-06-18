# AI Agent Repository Manifest: github-catalog

**ATTENTION LLM / AGENT:** Read this document immediately upon entering this repository. 

This repository implements a standalone, pure-Bash tool for building an append-only catalog of git repositories. It extracts semantic data and commit history without cloning full working trees and without using LLM summarization.

## Core Directives

1. **Architecture Reference:** You MUST read `docs/ADR-001-github-catalog-rewrite.md` before proposing architectural changes. 
2. **Zero Core Dependencies:** The core engine (`orchestrator` and `datafetcher`) is strictly restricted to Bash 5.0+, `jq` 1.7+, and standard `git`. 
   - **DO NOT** introduce Python, Node.js, BATS, or external APIs to the core engine.
   - **DO NOT** use LLMs to summarize or rewrite repository data. Extraction must remain deterministic via `awk`/`sed`.
3. **The API Bridge:** The `gh` CLI is *only* permitted inside `scripts/github-gh.sh`. This script acts as an isolated bridge to generate `user_repository` inventory lists.
4. **Data Storage:** State is maintained via append-only JSONL files in the `data/<user-name>/` directory. Never rewrite or overwrite existing JSONL lines.

## Project Structure

* `scripts/qobeat-repos.sh` - User-friendly wrapper script.
* `scripts/` - Execution entrypoints (Orchestrator, Datafetcher, GitHub API bridge).
* `tests/` - Pure-Bash test suite (Linters, Unit, Smoke).
* `docs/` - Architecture Decision Records and JSON Schema.
* `data/<user-name>/` - (Gitignored) Destination for JSONL banks (`user-repositories.jsonl`, `git-projects-catalog.jsonl`, `git-projects-commits.jsonl`).
* `reports/` - (Gitignored) Destination for generated markdown reports.
