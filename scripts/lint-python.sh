#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
lint-python.sh - compile-check and unit-test Python scripts

Options:
  -h, --help   Show this help

Runs:
  - bash syntax checks for GitHub Catalog shell entrypoints, when present
  - python3 -m py_compile for Python files under scripts/ and tests/
  - python3 -m unittest discover when tests/test_*.py exists
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: Unknown option: $1" >&2; usage; exit 2 ;;
  esac
done

SCRIPT_PATH="$(realpath "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd -- "$(dirname -- "$SCRIPT_PATH")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

shell_files=()
for f in scripts/github-catalog-orchestrator.sh scripts/github-catalog-datafetcher.sh scripts/lint-python.sh; do
  [[ -f "$f" ]] && shell_files+=("$f")
done
if ((${#shell_files[@]} > 0)); then
  echo "[bash -n] shell entrypoints"
  bash -n "${shell_files[@]}"
fi

mapfile -t py_files < <(find scripts tests -type f -name '*.py' 2>/dev/null | sort)
if ((${#py_files[@]} > 0)); then
  echo "[py_compile] Python files"
  python3 -m py_compile "${py_files[@]}"
else
  echo "[py_compile] no Python files found; skipping"
fi

if find tests -type f -name 'test_*.py' 2>/dev/null | grep -q .; then
  echo "[unittest] tests"
  PYTHONPATH="$REPO_ROOT/scripts${PYTHONPATH:+:$PYTHONPATH}" \
    python3 -m unittest discover -s tests -p 'test_*.py' -v
else
  echo "[unittest] no tests/test_*.py files found; skipping"
fi

echo "OK"
