# AI Agent Repository Manifest: github-catalog

**ATTENTION LLM / AGENT:** Read this document immediately upon entering this repository. 

This repository implements a standalone, pure-Bash tool for building an append-only catalog of git repositories. It extracts semantic data and commit history without cloning full working trees and without using LLM summarization.

## Core Directives

1. **Architecture Reference:** You MUST read `docs/ADR-001-github-catalog-rewrite.md` before proposing architectural changes. It contains the exact algorithms, schemas, and rationale for this project.
2. **Zero Dependencies:** This tool is strictly restricted to Bash 5.0+, `jq` 1.7+, and standard `git`. 
   - **DO NOT** introduce Python, Node.js, `gh` CLI, BATS, or external APIs.
   - **DO NOT** use LLMs to summarize or rewrite repository data. Extraction must remain deterministic via `awk`/`sed`.
3. **Data Storage:** State is maintained via append-only JSONL files in the `data/` directory. Never rewrite or overwrite existing JSONL lines.
4. **Agent Navigation:**
   - To execute the tool, read `scripts/MANIFEST.md`.
   - To run or modify tests, read `tests/MANIFEST.md`.

## Project Structure

* `scripts/` - Execution entrypoints (Orchestrator, Datafetcher, Report Generator).
* `tests/` - Pure-Bash test suite (Linters, Unit, Smoke).
* `docs/` - Architecture Decision Records and JSON Schema.
* `data/` - (Gitignored) Destination for `git-projects-catalog.jsonl` and `git-projects-commits.jsonl`.
* `reports/` - (Gitignored) Destination for generated markdown reports.