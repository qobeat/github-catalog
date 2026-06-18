#!/usr/bin/env bash
# tests/lint.sh - Run syntax and lint checks on shell scripts
set -euo pipefail

# Colors for terminal output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

# Find all shell scripts in the repository, ignoring cache, data, and git dirs
mapfile -t SH_FILES < <(find "$REPO_ROOT" -type f -name '*.sh' \
  -not -path "*/\.cache/*" \
  -not -path "*/data/*" \
  -not -path "*/\.git/*" | sort)

if (( ${#SH_FILES[@]} == 0 )); then
  echo "No shell scripts found."
  exit 0
fi

# 1. Syntax Check (bash -n)
echo "[1/2] Running bash syntax checks..."
ERRORS=0
for f in "${SH_FILES[@]}"; do
  if ! bash -n "$f"; then
    printf '%b✗ Syntax error in %s%b\n' "$RED" "${f#"$REPO_ROOT"/}" "$NC"
    ((ERRORS++))
  fi
done

if (( ERRORS > 0 )); then
  printf '%bFailed: %d files have syntax errors.%b\n' "$RED" "$ERRORS" "$NC"
  exit 1
fi
printf '%b✓ All files passed syntax check.%b\n\n' "$GREEN" "$NC"

# 2. ShellCheck Linting
echo "[2/2] Running ShellCheck..."
if command -v shellcheck >/dev/null 2>&1; then
  # Use -x to allow shellcheck to follow 'source' directives
  if shellcheck -x "${SH_FILES[@]}"; then
    printf '%b✓ ShellCheck passed.%b\n' "$GREEN" "$NC"
  else
    printf '%b✗ ShellCheck found issues.%b\n' "$RED" "$NC"
    exit 1
  fi
else
  printf '%b⚠ ShellCheck is not installed. Skipping linting.%b\n' "$YELLOW" "$NC"
  echo "  Install with: sudo apt install shellcheck"
fi

echo "All checks completed successfully."