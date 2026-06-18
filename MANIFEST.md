# **AI Agent Repository Manifest: github-catalog**

**ATTENTION LLM / AGENT:** Read this document immediately upon entering this repository.  
This project is an **Agent Development Lifecycle (ADLC)** compatible tool. It implements a standalone, pure-Bash tool for building an append-only catalog of git repositories, extracting semantic data (Goals, Objectives, Requirements) deterministically without LLM hallucination.

## **1. Core Directives & Constraints**

* **Architecture Reference:** You MUST adhere to [docs/ADR-001-github-catalog-rewrite.md](docs/ADR-001-github-catalog-rewrite.md) and [docs/ADR-002.md](docs/ADR-002.md).  
* **Zero Core Dependencies:** The engine is strictly restricted to Bash 5.0+, jq 1.7+, and standard git.  
  * **DO NOT** introduce Python, Node.js, BATS, or external APIs to the core execution logic.  
* **The API Bridge:** The `gh` CLI is *only* permitted inside `scripts/github-gh.sh` to run `gh repo list` (read-only inventory). No other script may call `gh` or network APIs.  
* **Read-Only GitHub:** Never add `git push`, `gh repo create/edit/delete`, or any mutating GitHub API call. Collection uses `git ls-remote` and `git clone --bare` only.  
* **Storage:** State is maintained via append-only JSONL files in `data/<user-name>/`. Never rewrite or overwrite existing JSONL lines.

## **2. The Unified CLI (`./github-catalog`)**

**Do not call internal scripts in `scripts/` directly.** Always use the unified root CLI.

```
./github-catalog <command> [arguments...]
```

### Command: `sync`

Fetches inventory (when needed) and appends snapshots/commits for matched repositories.

```
./github-catalog sync <owner> [glob] [flags...]
```

| Argument / flag | Required | Default | Description |
|---------------|----------|---------|-------------|
| `<owner>` | yes | — | Git host owner or org name. |
| `[glob]` | no | `*` | Shell glob on repo short names (e.g. `ados-*`). |
| `--private` | no | — | Only private repos. |
| `--public` | no | — | Only public repos. |
| `--all` | no | yes | All visibilities (default). |
| `--refresh` | no | off | Re-fetch inventory from GitHub via `gh` (up to 1000 repos). |
| `--git-host HOST` | no | `github.com` | SSH config Host alias for git URLs (e.g. `github-personal`). |
| `--ssh-key PATH` | no | — | Private key for git operations; optional when Host alias sets `IdentityFile`. |
| `--parallel N` | no | `4` | Max concurrent datafetcher workers. |

`gh` is required when prefetching inventory: wildcard globs, `--refresh`, or first sync without `--git-host` on a literal repo name. Wildcard matching applies **only** to prefetched inventory. Literal repo names can be probed via `git ls-remote` when missing from inventory (use `--git-host` for SSH aliases). Optional env: `GITHUB_CATALOG_GIT_HOST`, `GITHUB_CATALOG_SSH_KEY`.

```bash
./github-catalog sync qobeat ados-proj --git-host github-personal
./github-catalog sync qobeat 'ados-*' --git-host github-personal --refresh
./github-catalog sync qobeat 'ados-framework'   # uses cache if present
```

### Command: `report`

Generates a markdown summary from local JSONL.

```
./github-catalog report <owner>
```

| Argument | Required | Description |
|----------|----------|-------------|
| `<owner>` | yes | Owner to report on. Output: `reports/<owner>/latest.md`. |

```bash
./github-catalog report qobeat
```

### Command: `clean`

Removes local cached data (not GitHub).

```
./github-catalog clean <owner|all>
```

| Argument | Required | Description |
|----------|----------|-------------|
| `<owner>` | yes | Remove `data/<owner>/` and `reports/<owner>/`. |
| `all` | yes | Remove all `data/`, `reports/`, and `logs/` contents. |

```bash
./github-catalog clean qobeat
```

### Commands: `test` and `lint`

Always verify code modifications using the built-in pure-Bash harness.

```
./github-catalog test    # no arguments
./github-catalog lint    # no arguments
```

## **3. Directory Layout**

* `github-catalog` — unified CLI (primary interface)  
* `scripts/` — internal pipeline modules (Orchestrator, Fetcher, Reporter, GH-Bridge)  
* `tests/` — pure-Bash test suite  
* `docs/` — Architecture Decision Records and JSON Schema  
* `data/<user-name>/` — JSONL banks (gitignored)  
* `reports/<user-name>/` — generated markdown reports (gitignored)  
* `logs/` — structured run logs (gitignored)

## **4. Internal Scripts (reference only — do not invoke directly)**

Agents may read these for implementation context but must route all operations through `./github-catalog`:

| Script | Role |
|--------|------|
| `scripts/github-catalog-orchestrator.sh` | Parallel dispatch, inventory cache, run summary |
| `scripts/github-catalog-datafetcher.sh` | Per-repo sentry, bare clone, semantic extraction |
| `scripts/github-catalog-report.sh` | Pure-jq Markdown generation |
| `scripts/github-gh.sh` | Read-only `gh repo list` → `user-repositories.jsonl` |
