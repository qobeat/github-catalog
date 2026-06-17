# Cursor Prompt — Correct GitHub Catalog Tool Plan and Implementation

## GOAL

Correct the current `my-unix-scripts` GitHub repository catalog implementation so it becomes a dedicated, reusable `github-catalog` tool with explicit GOAL, OBJECTIVES, REQUIREMENTS in `README.md`, append-only JSONL data storage, shell entrypoints, a machine-readable schema, generated-data ignore rules, and local tests.

## CONTEXT

The current implementation already has useful pieces:

- `scripts/catalog_qobeat_repos.py` — deterministic Python collector using `gh api`, file caching, metadata extraction, markdown rendering.
- `scripts/catalog_qobeat_orchestrator.py` — Python parallel dispatcher.
- `docs/qobeat-private-repos.schema.json` — current catalog export schema.
- Current generated outputs: `docs/qobeat-private-repos.json` and `docs/qobeat-private-repos.md`.

The plan drift that must be corrected:

1. The tool is still too `qobeat`-specific in names and README framing.
2. Current output is mainly a materialized snapshot, not append-only history.
3. GOAL/OBJECTIVES/REQUIREMENTS are not defined as a dedicated README contract for the tool.
4. `requirements` is not yet a first-class extracted semantic bucket.
5. Generated private data is not clearly separated from tracked docs/schemas.
6. The current `scripts/lint-python.sh` fails in an empty-test state because `unittest discover` returns non-zero when no tests exist.

## FILES TO APPLY FROM THIS PACK

Copy these files into the repo, preserving paths:

- `README.md` → replace/update root `README.md` while preserving unrelated existing sections where applicable.
- `docs/github-catalog.schema.json` → add new tracked schema.
- `scripts/github-catalog-orchestrator.sh` → add executable shell orchestrator.
- `scripts/github-catalog-datafetcher.sh` → add executable shell datafetcher.
- `scripts/lint-python.sh` → replace current Python lint script.

After copying, run:

```bash
chmod +x scripts/github-catalog-orchestrator.sh scripts/github-catalog-datafetcher.sh scripts/lint-python.sh
```

## REQUIRED IMPLEMENTATION WORK

### 1. README

Ensure root `README.md` contains a dedicated section named exactly:

```markdown
## GitHub Catalog Tool
```

That section must include:

- `### GOAL`
- `### OBJECTIVES`
- `### REQUIREMENTS`
- `### Non-goals`
- `### Repository surfaces scanned`
- `### Files and folders`
- `### Scripts`
- `### Testing`
- `### Ignore rules`

Do not remove unrelated install/use information from the existing README.

### 2. Schema

Add `docs/github-catalog.schema.json` as the canonical schema for generated JSONL records and materialized catalog exports.

The schema must support these record types:

- `run`
- `repo_snapshot`
- `commit`
- materialized catalog export object

Add `requirements` as a first-class extracted field under `repo`, using the same shape as `goal` and `objectives`:

```json
{
  "text": "...verbatim...",
  "source_file": "APP-REQS.md",
  "source_heading": "Requirements"
}
```

### 3. Shell entrypoints

Add:

- `scripts/github-catalog-orchestrator.sh`
- `scripts/github-catalog-datafetcher.sh`

The shell scripts are the user-facing tool interface. They may call existing Python collector modules internally. Keep dependencies to:

- Bash
- Python standard library
- GitHub CLI `gh`
- native Linux utilities such as `date`, `mktemp`, and `flock` when available

Do not add external Python packages.

### 4. Python collector integration

Keep `scripts/catalog_qobeat_repos.py` as the current deterministic collector unless you rename it everywhere in one safe change.

Patch it to include:

- `requirements: ExtractedField | None` in `RepoCatalog`
- `requirements` in `catalog_to_dict`
- `requirements` in Markdown rendering
- heading/key aliases for requirements:
  - requirements
  - app requirements
  - governance requirements
  - constraints
  - obligations
  - acceptance criteria
- source priority unchanged except requirements should be extractable from `APP-REQS.md`, `project/APP-REQS.md`, `GOV-REQS.md`, `ados/GOV-REQS.md`, `MANIFEST.md`, and `README.md`.

Do not use GitHub API `description` as a fallback for goal, objectives, or requirements.

### 5. Append-only data layout

Create/observe this generated layout:

```text
data/github-catalog/catalog-snapshots.jsonl
data/github-catalog/repo-commits.jsonl
data/github-catalog/index.json
reports/github-catalog/latest.json
reports/github-catalog/latest.md
reports/github-catalog/history/
.cache/github-catalog/
```

Rules:

- `catalog-snapshots.jsonl` is append-only.
- One `repo_snapshot` line per repo per report run.
- `repo-commits.jsonl` is append-only and deduplicated by `(repo_slug, sha)` when commit history support is implemented.
- `index.json` is derived/rebuildable; it is not source of truth.
- Reports are generated materialized views, not source of truth.

### 6. Ignore generated files

Update `.gitignore` and `.ignore` if `.ignore` exists.

Add:

```gitignore
# GitHub Catalog generated private data
data/github-catalog/
reports/github-catalog/
.cache/github-catalog/

# Legacy qobeat catalog generated outputs
docs/qobeat-private-repos.json
docs/qobeat-private-repos.md
docs/qobeat-catalog/*.jsonl
docs/qobeat-catalog/index.json
```

Do not ignore:

- `docs/github-catalog.schema.json`
- source scripts
- tests
- README

### 7. Tests

Add or update tests under `tests/`.

Minimum required tests:

1. `scripts/lint-python.sh` succeeds even if there are no `tests/test_*.py` files.
2. `bash -n` passes for `scripts/github-catalog-orchestrator.sh`, `scripts/github-catalog-datafetcher.sh`, and `scripts/lint-python.sh`.
3. Offline smoke: run orchestrator with `--mock-catalog-json` and confirm `data/github-catalog/catalog-snapshots.jsonl` contains valid JSON lines.
4. Re-run the same mock input and confirm second run creates `collection_skipped: true` when the same synthetic HEAD is observed.
5. Unit test requirement extraction alias detection in the Python collector.
6. Unit test that GitHub API description is never used as fallback for GOAL/OBJECTIVES/REQUIREMENTS.

### 8. Verification commands

Run these before final response:

```bash
bash -n scripts/github-catalog-orchestrator.sh scripts/github-catalog-datafetcher.sh scripts/lint-python.sh
./scripts/lint-python.sh

rm -rf /tmp/github-catalog-data
scripts/github-catalog-orchestrator.sh \
  --mock-catalog-json /path/to/qobeat-private-repos-smoke.json \
  --repos 'ados-*' \
  --type private \
  --parallel 2 \
  --limit 3 \
  --data-dir /tmp/github-catalog-data

python3 - <<'PY'
import json, pathlib
p = pathlib.Path('/tmp/github-catalog-data/catalog-snapshots.jsonl')
lines = p.read_text().splitlines()
assert lines, 'no snapshot lines written'
for line in lines:
    obj = json.loads(line)
    assert obj['record_type'] == 'repo_snapshot'
    assert obj['repo']['slug']
print(f'OK snapshots={len(lines)}')
PY
```

For live verification on the developer machine with authenticated `gh`:

```bash
scripts/github-catalog-orchestrator.sh \
  --user qobeat \
  --repos 'ados-*' \
  --type private \
  --parallel 5 \
  --limit 3 \
  --no-line-counts
```

## ACCEPTANCE CRITERIA

The change is acceptable only if:

- README has explicit GOAL, OBJECTIVES, REQUIREMENTS for the GitHub Catalog Tool.
- The tool has shell entrypoints named `github-catalog-orchestrator.sh` and `github-catalog-datafetcher.sh`.
- The schema file is valid JSON and includes `requirements` under `repo`.
- Generated private data paths are ignored.
- `scripts/lint-python.sh` passes in the current repo state.
- Mock offline smoke test writes valid JSONL without requiring `gh`.
- No external Python dependencies are introduced.
- Existing collector behavior for current JSON/Markdown export is not broken.

## DO NOT

- Do not clone repositories.
- Do not summarize or rewrite repo semantic fields with an LLM.
- Do not introduce `jq`, `requests`, `pydantic`, `jsonschema`, Node, or non-stdlib dependencies.
- Do not commit generated private catalog data.
- Do not remove unrelated existing scripts or README sections.
- Do not rename existing Python modules unless all references are updated and tests pass.
