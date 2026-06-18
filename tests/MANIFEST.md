# Test Manifest for AI Coding Agents

**ATTENTION LLM / AGENT:** Read this document before attempting to run, modify, or debug tests in this repository.

This project uses a **strict, pure-Bash** testing architecture. Do not attempt to use Python `unittest`, `pytest`, BATS, or any other external testing framework. The former `scripts/lint-python.sh` helper was removed in favor of `tests/lint.sh` and `tests/test.sh`.

## Testing Contracts & Rules

1. **Zero External Dependencies:** Tests rely only on standard POSIX tools, Bash 5.0+, `git`, and `jq`.
2. **File Naming:** Unit test files live in `tests/` and are prefixed with `test_` (e.g. `tests/test_extraction.sh`).
3. **Function Naming:** Every test case must be a function prefixed with `test_` (e.g. `test_sentry_skip_logic()`). The runner discovers and executes these automatically.
4. **Isolation:** The runner executes every test function in a subshell `( "$t" )`. It is safe to manipulate environment variables, mock functions, or use `trap` inside a test without polluting other tests.
5. **Smoke Tests:** Offline integration tests live in `tests/smoke-test.sh` (not auto-discovered as `test_*.sh`). `tests/test.sh` invokes smoke tests after unit tests.

## How to Verify Your Work

As an agent, you MUST run these commands to verify your shell script changes.

### 1. The Quick Check (do this constantly)

If you only changed one file, do a fast, zero-cost syntax check:

```bash
bash -n scripts/github-catalog-orchestrator.sh
# OR
bash -n scripts/github-catalog-datafetcher.sh
# OR
bash -n scripts/github-catalog-report.sh
```

### 2. Lint (syntax + ShellCheck)

```bash
./tests/lint.sh
```

Expected exit code: **0**. ShellCheck must report zero issues when installed.

### 3. Unit + Smoke Tests

```bash
./tests/test.sh
```

Expected exit code: **0**. Output ends with `Passed: N | Failed: 0` and smoke tests print `PASS: sentry logic OK` and `PASS: report generation OK`.

### 4. Smoke Tests Only

```bash
./tests/smoke-test.sh
```

Use when working on datafetcher sentry logic or report generation.

## Test File Inventory

| File | Purpose |
| --- | --- |
| `tests/lint.sh` | Runs `bash -n` and `shellcheck -x` on all `*.sh` files |
| `tests/test.sh` | Assertion helpers, unit test runner, smoke test orchestration |
| `tests/test_extraction.sh` | README semantic extraction (matches datafetcher `extract_section`) |
| `tests/test_orchestrator.sh` | Owner normalization, glob matching, repo-list parsing |
| `tests/test_schema.sh` | JSONL record shape validation against schema conventions |
| `tests/smoke-test.sh` | Offline bare-repo sentry skip + report generation (ADR steps 14–15) |

## Adding New Tests

1. Create `tests/test_<area>.sh`.
2. Define functions named `test_<description>()`.
3. Use `assert_eq`, `assert_match` from the runner (available after `tests/test.sh` sources your file).
4. Run `./tests/test.sh` and confirm zero failures.
5. If adding integration coverage that needs git fixtures, extend `tests/smoke-test.sh` or add a new standalone smoke script and wire it from `tests/test.sh`.

## Expected Exit Codes

| Command | Success | Failure |
| --- | --- | --- |
| `./tests/lint.sh` | 0 | 1 (syntax or ShellCheck error) |
| `./tests/test.sh` | 0 | 1 (unit or smoke failure) |
| `./tests/smoke-test.sh` | 0 | 1 (integration failure) |
