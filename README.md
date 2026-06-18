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

**Behavior notes:**

- On first sync for an owner, `gh` fetches the repo list (up to 1000 repos) unless syncing a **literal** repo name with `--git-host` (inventory skipped; repo probed via `git ls-remote`).
- **Wildcard globs** match only repos in prefetched inventory (`user-repositories.jsonl`); use `--refresh` after `gh auth login` if inventory is stale or from the wrong account.
- **Literal repo names** not in inventory are probed directly via git before failing.
- Subsequent syncs reuse cached inventory unless `--refresh` is passed.
- `--type` visibility filtering applies to both fresh fetches and cached inventory.
- Matched repos are collected in parallel; output is appended to JSONL under `data/<owner>/`.
- Optional env vars: `GITHUB_CATALOG_GIT_HOST`, `GITHUB_CATALOG_SSH_KEY`.

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

### `report` — generate Markdown from JSONL

```
./github-catalog report <owner>
```

| Argument | Required | Description |
|----------|----------|-------------|
| `<owner>` | yes | Owner whose catalog to report on. |

Reads `data/<owner>/git-projects-catalog.jsonl` and writes a timestamped report under `reports/<owner>/report-<timestamp>.md`. Updates `reports/<owner>/latest.md` as a symlink to the newest report.

```bash
./github-catalog report qobeat
```

### `clean` — remove local cache

```
./github-catalog clean <owner|all>
```

| Argument | Required | Description |
|----------|----------|-------------|
| `<owner>` | yes | Owner whose `data/<owner>/` and `reports/<owner>/` directories are removed. |
| `all` | yes | Remove all contents of `data/`, `reports/`, and `logs/`. |

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

## **Testing & Development**

```bash
./github-catalog lint
./github-catalog test
```
