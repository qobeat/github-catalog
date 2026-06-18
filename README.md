# **github-catalog**

A minimalistic, zero-dependency (Bash/jq/git) CLI tool for building an append-only catalog of git repositories. It extracts semantic documentation (Goals, Objectives, Requirements) and commit history without cloning full working trees and without using LLMs.  
This project follows strict OSINT and ADLC principles: deterministic execution, verifiable evidence, and strict environment isolation. Read the architecture specification in [docs/ADR-001-github-catalog-rewrite.md](docs/ADR-001-github-catalog-rewrite.md) and the unified CLI design in [docs/ADR-002.md](docs/ADR-002.md).

## **Prerequisites**

* **Bash 5.0+** — required for parallel `wait -n` job control  
* **jq 1.7+** — required for JSONL stream processing  
* **git** — required for `ls-remote` and bare clones (read-only against remotes)  
* **gh** — required on **first sync** (no cached `user-repositories.jsonl`) or when using `--refresh`; not needed when a cached inventory exists

All GitHub interaction is **read-only** (`gh repo list`, `git ls-remote`, `git clone --bare`). Nothing is written to GitHub.

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
| `--refresh` | no | off | Force a fresh inventory fetch from GitHub via `gh` (appends to `user-repositories.jsonl`). |
| `--parallel N` | no | `4` | Maximum concurrent repository workers. |

**Behavior notes:**

- On first sync for an owner, `gh` fetches the repo list because `data/<owner>/user-repositories.jsonl` does not exist yet.
- Subsequent syncs reuse the cached inventory unless `--refresh` is passed.
- `--type` visibility filtering applies to both fresh fetches and cached inventory.
- Matched repos are collected in parallel; output is appended to JSONL under `data/<owner>/`.

**Examples:**

```bash
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

Reads `data/<owner>/git-projects-catalog.jsonl` and writes `reports/<owner>/latest.md`.

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
  ├── user-repositories.jsonl      # Discovered inventory (via gh, append-only)
  ├── git-projects-catalog.jsonl   # Append-only semantic snapshots
  └── git-projects-commits.jsonl     # Append-only commit history

reports/<owner>/
  └── latest.md                    # Generated pure-jq report

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
