# **AI Agent Repository Manifest: github-catalog**

**ATTENTION LLM / AGENT:** Read this document immediately upon entering this repository.  
This project is an **Agent Development Lifecycle (ADLC)** compatible tool. It implements a standalone, pure-Bash tool for building an append-only catalog of git repositories, extracting semantic data (Goals, Objectives, Requirements) deterministically without LLM hallucination.

## **1. Core Directives & Constraints**

* **Architecture Reference:** You MUST adhere to [docs/ADR-001-github-catalog-rewrite.md](docs/ADR-001-github-catalog-rewrite.md) (engine), [docs/ADR-002.md](docs/ADR-002.md) (UX/AX layer), and [docs/ADR-003.md](docs/ADR-003.md) (P0+P1 UX/AX — implemented). [ADR-004](docs/ADR-004.md) and [ADR-005](docs/ADR-005.md) are **proposed** roadmap.  
* **Zero Core Dependencies:** The engine is strictly restricted to Bash 5.0+, jq 1.7+, and standard git.  
  * **DO NOT** introduce Python, Node.js, BATS, or external APIs to the core execution logic.  
* **The API Bridge:** The `gh` CLI is *only* permitted inside `scripts/github-gh.sh` to run `gh repo list` / `gh repo view` (read-only inventory). No other script may call `gh` or network APIs.  
* **Read-Only GitHub:** Never add `git push`, `gh repo create/edit/delete`, or any mutating GitHub API call. Collection uses `git ls-remote` and `git clone --bare` only.  
* **Storage:** State is maintained via append-only JSONL files in `data/<user-name>/`. Never rewrite or overwrite existing JSONL lines.

## **2. The Unified CLI (`./github-catalog`)**

**Do not call internal scripts in `scripts/` directly.** Always use the unified root CLI.

```
./github-catalog <command> [arguments...]
```

### Exit codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | Partial failure (workers failed; catalog may still be written) |
| 2 | Usage / bad arguments |
| 3 | Precondition failed (missing `gh`, missing catalog, no repos matched) |

### Per-owner config

Optional `data/<owner>/catalog.config` (flat `key=value`, `#` comments). Keys: `git_host`, `ssh_key`, `visibility` (`private|public|all`), `parallel`.

Precedence: **CLI flag** > **`GITHUB_CATALOG_*` env** > **`catalog.config`** > **default**.

Env vars: `GITHUB_CATALOG_GIT_HOST`, `GITHUB_CATALOG_SSH_KEY`, `GITHUB_CATALOG_PARALLEL`, `GITHUB_CATALOG_VISIBILITY`.

`clean <owner>` preserves `catalog.config` unless `--purge`.

### Command: `doctor`

Preflight / self-diagnosis (read-only).

```
./github-catalog doctor [owner] [--git-host HOST]
```

### Command: `status`

Fast catalog overview without writing a report.

```
./github-catalog status [owner] [--format text|json]
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
| `--dry-run` | no | off | Sentry only; print planned actions, no writes. |
| `--quiet` | no | auto | Suppress progress bar (auto when stderr not a TTY). |
| `--verbose` | no | off | Mirror log lines to stderr. |

`gh` is required when prefetching inventory: wildcard globs, `--refresh`, or first sync without `--git-host` on a literal repo name. On success, prints a one-line stdout summary with next-step hint (`report`).

```bash
./github-catalog sync qobeat ados-proj --git-host github-personal
./github-catalog sync qobeat 'ados-*' --dry-run
./github-catalog sync qobeat 'ados-framework'   # uses cache if present
```

### Command: `refresh`

Inventory-only update — fetches `user-repositories.jsonl` from GitHub via `gh` (`gh repo list` for an owner, `gh repo view` for a single repo) **without** cataloging content. Repos absent from GitHub within the visibility scope are tombstoned (`status: deleted`). Always requires authenticated `gh`.

```
./github-catalog refresh <owner|owner/repo> [--private|--public|--all]
```

| Argument | Required | Description |
|----------|----------|-------------|
| `<owner>` | yes | Refresh the whole owner inventory. |
| `<owner>/<repo>` | — | Refresh a single repository entry. |

```bash
./github-catalog refresh qobeat
./github-catalog refresh qobeat/ados-proj --public
```

### Command: `report`

Generates a markdown or JSON summary from local JSONL.

```
./github-catalog report <owner> [--format md|json]
```

| Argument / flag | Required | Default | Description |
|----------|----------|---------|-------------|
| `<owner>` | yes | — | Owner to report on. |
| `--format` | no | `md` | `md` → `reports/<owner>/report-<timestamp>.md` + `latest.md`; `json` → stdout. |

```bash
./github-catalog report qobeat
./github-catalog report qobeat --format json
```

### Command: `clean`

Removes local cached data (not GitHub).

```
./github-catalog clean <owner|all> [--purge]
```

| Argument | Required | Description |
|----------|----------|-------------|
| `<owner>` | yes | Remove data/reports for owner; preserves `catalog.config` unless `--purge`. |
| `all` | yes | Remove all `data/`, `reports/`, and `logs/` contents. |
| `--purge` | no | Also delete `catalog.config`. |

```bash
./github-catalog clean qobeat
```

### Commands: `test` and `lint`

Always verify code modifications using the built-in pure-Bash harness. For any substantive change, run the full suite (lint is included automatically):

```
./github-catalog test    # lint + unit tests + smoke tests
./github-catalog lint    # syntax + ShellCheck only (also run by test)
```

## **3. Directory Layout**

* `github-catalog` — unified CLI (primary interface)  
* `scripts/` — internal pipeline modules (Orchestrator, Fetcher, Reporter, GH-Bridge, Doctor, Status, shared lib/jq)  
* `tests/` — pure-Bash test suite  
* `docs/` — Architecture Decision Records and JSON Schema  
* `data/<user-name>/` — JSONL banks + optional `catalog.config` (gitignored)  
* `reports/<user-name>/` — generated markdown reports (gitignored)  
* `logs/` — structured run logs (gitignored)

## **4. Internal Scripts (reference only — do not invoke directly)**

Agents may read these for implementation context but must route all operations through `./github-catalog`:

| Script | Role |
|--------|------|
| `scripts/github-catalog-lib.sh` | Shared exit codes, config loader, TTY/version helpers |
| `scripts/github-catalog-orchestrator.sh` | Parallel dispatch, dry-run, quiet/verbose, stdout summary |
| `scripts/github-catalog-datafetcher.sh` | Per-repo sentry, bare clone, semantic extraction, dry-run |
| `scripts/github-catalog-refresh.sh` | Inventory-only refresh (full owner or single repo) |
| `scripts/github-catalog-report.sh` | Pure-jq report aggregation (`report-data.jq`) → md or json |
| `scripts/github-catalog-status.sh` | Fast catalog digest (text or json) |
| `scripts/github-catalog-doctor.sh` | Preflight checks |
| `scripts/github-gh.sh` | Read-only `gh repo list` / `gh repo view` → `user-repositories.jsonl`; deletion tombstones |
