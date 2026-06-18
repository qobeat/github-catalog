# **github-catalog**

A minimalistic, zero-dependency (Bash/jq/git) CLI tool for building an append-only catalog of git repositories. It extracts semantic documentation (Goals, Objectives, Requirements) and commit history without cloning full working trees and without using LLMs.  
This project follows strict OSINT and ADLC principles: deterministic execution, verifiable evidence, and strict environment isolation. Read the architecture specification in [docs/ADR-001-github-catalog-rewrite.md](docs/ADR-001-github-catalog-rewrite.md) and the unified CLI design in [docs/ADR-002.md](docs/ADR-002.md).

## **Prerequisites**

* **Bash 5.0+** — required for parallel `wait -n` job control  
* **jq 1.7+** — required for JSONL stream processing  
* **git** — required for `ls-remote` and bare clones (read-only against remotes)  
* **gh** — required when prefetching inventory (wildcard globs, `--refresh`, or first sync without `--git-host` on a literal repo); not needed for cached inventory or single-repo sync with `--git-host`

All GitHub interaction is **read-only** (`gh repo list`, `git ls-remote`, `git clone --bare`). Nothing is written to GitHub.

## **Dual authentication: why sync can fail**

github-catalog uses **two independent paths** to reach GitHub. They do not share credentials:

| Path | Tool | Used for | Typical auth |
|------|------|----------|--------------|
| Inventory | `gh repo list` | Prefetch repo names for wildcard globs (up to 1000 repos) | `gh auth login` token |
| Collection | `git ls-remote` / `git clone --bare` | Read repo content and history | SSH keys via `~/.ssh/config` Host aliases |

This split caused false "repo not found" errors before `--git-host` existed:

1. **`gh` on the wrong account** — inventory never lists private repos owned by another GitHub user, even though `git ls-remote git@github-personal:owner/repo.git` works.
2. **Default clone URL** — inventory stores HTTPS URLs from `gh`; the datafetcher defaulted to `git@github.com:owner/repo.git`. Neither matches an SSH Host alias like `github-personal` with its own `IdentityFile`.

Symptoms: `./github-catalog sync qobeat ados-proj` fails with "no repository reachable at git@github.com:…" while `git ls-remote git@github-personal:qobeat/ados-proj.git` succeeds.

**Mitigations:**

- Pass **`--git-host`** (SSH config Host alias) so git operations use the correct key/account.
- For **wildcard globs**, repos must appear in prefetched inventory — run `gh auth login` for the owner account, then `--refresh`.
- For a **single known repo**, sync by literal name with `--git-host`; inventory and `gh` are skipped on first run.

See [docs/ADR-002.md](docs/ADR-002.md) for the full design rationale.

## **Getting started from zero**

Replace `qobeat` with your GitHub owner/org name. These workflows assume a fresh clone with no `data/<owner>/` cache.

### Workflow A — standard (one GitHub account, `gh` and git both work)

**First run** — prefetch inventory, catalog matching repos, generate report:

```bash
# 1. Authenticate gh for the owner account (once per machine)
gh auth login

# 2. Prefetch up to 1000 repos and catalog all matching a glob
./github-catalog sync qobeat 'ados-*' --refresh

# 3. Read the markdown summary
./github-catalog report qobeat
# → reports/qobeat/report-<timestamp>.md (latest.md symlink points to newest)
```

**Second run** — reuse cached inventory; only repos with new commits are re-collected (sentry skip):

```bash
# No gh call; uses data/qobeat/user-repositories.jsonl from first run
./github-catalog sync qobeat 'ados-*'

# Refresh report from updated JSONL
./github-catalog report qobeat
```

To pick up newly created repos or fix stale inventory:

```bash
./github-catalog sync qobeat 'ados-*' --refresh
```

### Workflow B — SSH Host alias (`gh` and git use different accounts/keys)

Typical when `~/.ssh/config` defines `Host github-personal` with a dedicated key, but `gh auth status` shows another user.

**First run** — two-step: build inventory for wildcards, then catalog via SSH alias:

```bash
# 1. Prefetch inventory (gh must see the owner's repos — log in as that user if needed)
gh auth login
./github-catalog sync qobeat '*' --refresh

# 2. Catalog with SSH alias (rewrites clone URLs to git@github-personal:qobeat/<repo>.git)
./github-catalog sync qobeat 'ados-*' --git-host github-personal

# 3. Report
./github-catalog report qobeat
```

**Or**, for a single repo you already know, skip inventory entirely on first run:

```bash
./github-catalog sync qobeat ados-proj --git-host github-personal
./github-catalog report qobeat
```

**Second run** — cached inventory + SSH alias; no gh unless refreshing:

```bash
./github-catalog sync qobeat 'ados-*' --git-host github-personal
./github-catalog report qobeat
```

Optional explicit key instead of relying on `IdentityFile` in SSH config:

```bash
./github-catalog sync qobeat ados-proj \
  --git-host github-personal \
  --ssh-key ~/.ssh/id_ed25519_personal
```

Persistent defaults via environment (documented convenience):

```bash
export GITHUB_CATALOG_GIT_HOST=github-personal
./github-catalog sync qobeat 'ados-*'
```

Or per-owner config file (see [Per-owner config](#per-owner-config) below).

### Preflight with `doctor`

Before your first sync — especially with SSH host aliases — run:

```bash
./github-catalog doctor qobeat --git-host github-personal
```

This checks bash/jq/git, `gh` authentication, SSH reachability, and local inventory state.

## **CLI Reference**

Operate exclusively through the root executable:

```
./github-catalog <command> [arguments...]
```

### `sync` — fetch inventory and catalog repositories

```
./github-catalog sync <owner> [glob] [flags...]
```

| Argument / flag | Required | Default | Description |
|---------------|----------|---------|-------------|
| `<owner>` | yes | — | Git host owner or org (e.g. `qobeat`). URL forms like `https://github.com/qobeat` are accepted by internal scripts. |
| `[glob]` | no | `*` | Shell glob matching repository short names (e.g. `ados-*`, `ados-framework`). Omit to match all repos in inventory. |
| `--private` | no | — | Restrict to private repositories. Mutually exclusive with `--public`; overrides default `--all`. |
| `--public` | no | — | Restrict to public repositories. |
| `--all` | no | yes | Include repositories of any visibility (default when neither `--private` nor `--public` is set). |
| `--refresh` | no | off | Force a fresh inventory fetch from GitHub via `gh` (appends to `user-repositories.jsonl`, up to 1000 repos). Repos removed from GitHub within the same visibility scope are tombstoned with `status: deleted`. |
| `--git-host HOST` | no | `github.com` | SSH config Host alias for git clone URLs (e.g. `github-personal` from `~/.ssh/config`). |
| `--ssh-key PATH` | no | — | Private key for git operations; optional when the Host alias already sets `IdentityFile`. |
| `--parallel N` | no | `4` | Maximum concurrent repository workers. |
| `--dry-run` | no | off | Run sentry (`git ls-remote`) only; print planned collect/skip/unreachable actions; no writes. |
| `--quiet` | no | auto | Suppress progress bar (auto-enabled when stderr is not a TTY). |
| `--verbose` | no | off | Mirror structured log lines to stderr in real time. |

**Behavior notes:**

- On first sync for an owner, `gh` fetches the repo list (up to 1000 repos) unless syncing a **literal** repo name with `--git-host` (inventory skipped; repo probed via `git ls-remote`).
- **Wildcard globs** match only repos in prefetched inventory (`user-repositories.jsonl`); use `--refresh` after `gh auth login` if inventory is stale or from the wrong account.
- **Literal repo names** not in inventory are probed directly via git before failing.
- Subsequent syncs reuse cached inventory unless `--refresh` is passed.
- `--type` visibility filtering applies to both fresh fetches and cached inventory.
- Matched repos are collected in parallel; output is appended to JSONL under `data/<owner>/`.
- Optional env vars: `GITHUB_CATALOG_GIT_HOST`, `GITHUB_CATALOG_SSH_KEY`, `GITHUB_CATALOG_PARALLEL`, `GITHUB_CATALOG_VISIBILITY`.
- Per-owner defaults: `data/<owner>/catalog.config` (see below).
- On success, prints a one-line stdout summary with collect/skip/fail counts and a suggested next step (`report`).

**Examples:**

```bash
# SSH alias account: sync one private repo without gh inventory
./github-catalog sync qobeat ados-proj --git-host github-personal

# Wildcard: prefetch inventory via gh, clone via SSH alias
./github-catalog sync qobeat 'ados-*' --git-host github-personal --refresh

# First sync: fetches inventory from GitHub, then catalogs matching repos
./github-catalog sync qobeat 'ados-framework'

# Force inventory refresh, private repos only, glob filter
./github-catalog sync qobeat 'ados-*' --private --refresh

# Cached run: no gh call, sync all repos matching glob
./github-catalog sync qobeat '*' --parallel 8
```

### `refresh` — update inventory only (no collection)

```
./github-catalog refresh <owner|owner/repo> [--private|--public|--all]
```

| Argument / flag | Required | Default | Description |
|---------------|----------|---------|-------------|
| `<owner>` | yes | — | Refresh the full repo inventory for an owner/org. URL forms like `https://github.com/qobeat` accepted. |
| `<owner>/<repo>` | — | — | Refresh a single repository entry instead of the whole owner. |
| `--private` / `--public` / `--all` | no | `--all` | Visibility filter. |

Fetches `data/<owner>/user-repositories.jsonl` from GitHub via `gh` **without** cataloging repo content (no clone, no semantic extraction). Repos that disappeared from GitHub within the selected visibility scope are tombstoned in inventory (`status: deleted`). Always requires authenticated `gh`. Use it to pick up newly created, renamed, or deleted repos before a `sync` — or to seed inventory for a single private repo without a wildcard fetch.

```bash
./github-catalog refresh qobeat                      # whole owner, all visibilities
./github-catalog refresh qobeat/ados-proj --public   # single repo
```

### `doctor` — preflight checks

```
./github-catalog doctor [owner] [--git-host HOST]
```

Read-only checklist: bash/jq/git versions, `gh` auth (if installed), SSH probe (when owner + git-host given), local inventory/catalog state.

```bash
./github-catalog doctor
./github-catalog doctor qobeat --git-host github-personal
```

### `status` — fast catalog overview

```
./github-catalog status [owner] [--format text|json]
```

Compact digest without writing a report file. Without an owner, lists all cataloged owners under `data/`.

```bash
./github-catalog status
./github-catalog status qobeat
./github-catalog status qobeat --format json
```

### `report` — generate report from JSONL

```
./github-catalog report <owner> [--format md|json]
```

| Argument / flag | Required | Default | Description |
|---------------|----------|---------|-------------|
| `<owner>` | yes | — | Owner whose catalog to report on. |
| `--format` | no | `md` | `md` writes timestamped Markdown under `reports/<owner>/`; `json` prints aggregation to stdout. |

Reads `data/<owner>/git-projects-catalog.jsonl` (and commits JSONL when present). Markdown output updates `reports/<owner>/latest.md` symlink.

```bash
./github-catalog report qobeat
./github-catalog report qobeat --format json
```

### `clean` — remove local cache

```
./github-catalog clean <owner|all> [--purge]
```

| Argument / flag | Required | Description |
|----------|----------|-------------|
| `<owner>` | yes | Remove `data/<owner>/` (except `catalog.config` unless `--purge`) and `reports/<owner>/`. |
| `all` | — | Remove all `data/`, `reports/`, and `logs/` contents. |
| `--purge` | no | Also delete `catalog.config` when cleaning a single owner. |

Does not modify anything on GitHub.

```bash
./github-catalog clean qobeat
./github-catalog clean all
```

### `test` — run unit and smoke tests

```
./github-catalog test
```

No arguments. Runs syntax checks, pure-Bash unit tests, and offline integration smoke tests.

### `lint` — run syntax and ShellCheck

```
./github-catalog lint
```

No arguments. Runs `bash -n` on all shell scripts and ShellCheck when installed.

## **Data Architecture**

All output is partitioned by the target owner and isolated from version control (`.gitignore` applied).

```
data/<owner>/
  ├── catalog.config               # Optional per-owner defaults (git_host, visibility, parallel, ssh_key)
  ├── user-repositories.jsonl      # Discovered inventory (via gh, append-only; status: active|deleted)
  ├── git-projects-catalog.jsonl   # Append-only semantic snapshots (status: active|deleted)
  └── git-projects-commits.jsonl     # Append-only commit history (immutable; status on new lines)

reports/<owner>/
  ├── report-YYYY-MM-DDTHH-MM-SSZ.md   # Versioned markdown reports (never overwritten)
  └── latest.md                        # Symlink to the most recent report

logs/
  └── github-catalog-<date>.log    # Structured run log
```

### **Schemas**

JSONL records adhere to [docs/github-catalog.schema.json](docs/github-catalog.schema.json):

```bash
jq '.' docs/github-catalog.schema.json
```

### Per-owner config

Optional flat `key=value` file at `data/<owner>/catalog.config` (comments with `#` supported):

```
git_host=github-personal
visibility=private
parallel=8
ssh_key=~/.ssh/id_ed25519_personal
```

Precedence: **CLI flag** > **`GITHUB_CATALOG_*` env** > **`catalog.config`** > **built-in default**.

`clean <owner>` preserves `catalog.config` unless `--purge` is passed.

### Exit codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | Partial failure (e.g. one or more workers failed; catalog still written) |
| 2 | Usage / bad arguments |
| 3 | Precondition failed (missing `gh`, missing catalog, no repos matched) |

## **Testing & Development**

```bash
./github-catalog lint
./github-catalog test
```

## **Architecture decision records**

| ADR | Status | Scope |
|-----|--------|-------|
| [ADR-001](docs/ADR-001-github-catalog-rewrite.md) | Accepted | Pure Bash/jq/git engine, JSONL streams, sentry skip logic |
| [ADR-002](docs/ADR-002.md) | Accepted | Unified CLI, dual-auth (`--git-host`), lifecycle tombstones, report UX/AX |
| [ADR-003](docs/ADR-003.md) | Accepted (P0+P1) | doctor, status, config file, JSON report, dry-run, exit codes; P2 deferred |
| [ADR-004](docs/ADR-004.md) | Proposed | Repository intelligence — deterministic archetype classification |
| [ADR-005](docs/ADR-005.md) | Proposed | `github-catalog-mcp` — Model Context Protocol server |
