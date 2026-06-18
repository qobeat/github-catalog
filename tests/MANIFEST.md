# Test Manifest for AI Coding Agents

**ATTENTION LLM / AGENT:** Read this document before attempting to run, modify, or debug tests in this repository.

This project uses a **strict, pure-Bash** testing architecture. Do not attempt to use Python `unittest`, `pytest`, BATS, or any other external testing framework. 

## Testing Contracts & Rules

1. **Zero External Dependencies:** Tests rely only on standard POSIX tools, `jq`, and Bash 5.0+.
2. **File Naming:** All unit test files must be placed in the `tests/` directory and prefixed with `test_` (e.g., `test_orchestrator.sh`).
3. **Function Naming:** Every test case inside a test file must be a function prefixed with `test_` (e.g., `test_sentry_skip_logic()`). The runner automatically discovers and executes these.
4. **Isolation:** The runner executes every test function in a subshell `( "$t" )`. It is safe to manipulate environment variables, mock functions, or use `trap` inside a test without polluting other tests.

## How to Verify Your Work

As an agent, you MUST run these commands to verify your shell script changes.

### 1. The Quick Check (Do this constantly)
If you only changed one file, do a fast, zero-cost syntax check to ensure no missing quotes or bad loops.
```bash
bash -n scripts/github-catalog-orchestrator.sh
# OR
bash -n scripts/github-catalog-datafetcher.sh

```

### 2. The Full Lint (Do this before finalizing code)

This runs global syntax checks and `shellcheck` across all shell scripts in the repository. It will catch unquoted variables and bad practices.

```bash
./tests/lint.sh

```

### 3. Run the Unit Tests

Execute the pure-Bash test runner. This will discover all `test_*.sh` files and run their functions.

```bash
./tests/test.sh

```

## Available Assertions

When writing new tests, source the assertion helpers (if needed) or rely on the globals injected by `test.sh`.

* `assert_eq "expected" "actual" "optional message"`
* `assert_match "regex" "actual_string"`
