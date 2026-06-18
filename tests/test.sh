#!/usr/bin/env bash
# tests/test.sh - Pure Bash Unit Test Runner
set -euo pipefail

PASSED=0
FAILED=0

# Colors for terminal output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# --- Assertion Helpers ---
assert_eq() {
  local expected="$1"
  local actual="$2"
  local msg="${3:-}"
  if [[ "$expected" == "$actual" ]]; then
    return 0
  else
    printf '%bASSERT FAIL:%b Expected '"'%s'"', got '"'%s'"' %s\n' "$RED" "$NC" "$expected" "$actual" "${msg:+- $msg}" >&2
    return 1
  fi
}

assert_match() {
  local regex="$1"
  local actual="$2"
  if [[ "$actual" =~ $regex ]]; then
    return 0
  else
    printf '%bASSERT FAIL:%b Value '"'%s'"' does not match regex '"'%s'"'\n' "$RED" "$NC" "$actual" "$regex" >&2
    return 1
  fi
}

# --- Runner Logic ---
run_tests() {
  local test_files=("$@")
  
  for tf in "${test_files[@]}"; do
    printf "Running tests in %s...\n" "${tf#"$REPO_ROOT"/}"
    
    # Source the test file to discover functions
    # shellcheck source=/dev/null
    source "$tf"
    
    # Discover all functions starting with 'test_'
    local tests
    mapfile -t tests < <(declare -F | awk '{print $3}' | grep '^test_')
    
    for t in "${tests[@]}"; do
      # Run test in a subshell to isolate environment variables and traps
      if ( "$t" ); then
        printf '  %b✓%b %s\n' "$GREEN" "$NC" "$t"
        PASSED=$((PASSED + 1))
      else
        printf '  %b✗%b %s\n' "$RED" "$NC" "$t"
        FAILED=$((FAILED + 1))
      fi
    done
    
    # Cleanup namespace
    for t in "${tests[@]}"; do unset -f "$t"; done
  done

  echo "==================================="
  echo "Passed: $PASSED | Failed: $FAILED"
  (( FAILED == 0 )) || exit 1
}

# --- Execution ---
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

# 1. Syntax and ShellCheck (same as ./github-catalog lint)
echo "[lint] syntax and ShellCheck"
"$SCRIPT_DIR/lint.sh"

# 2. Discover and run unit tests
mapfile -t files < <(find "$REPO_ROOT/tests" -type f -name 'test_*.sh' 2>/dev/null | sort)

if ((${#files[@]} > 0)); then
  run_tests "${files[@]}"
else
  echo "No test_*.sh files found."
fi

# 3. Offline integration smoke tests (ADR steps 14–15)
if [[ -x "$SCRIPT_DIR/smoke-test.sh" ]]; then
  echo ""
  echo "[smoke] offline integration tests"
  "$SCRIPT_DIR/smoke-test.sh"
fi