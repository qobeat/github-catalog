#!/usr/bin/env bash
# scripts/qobeat-repos.sh - User wrapper for the GitHub Catalog orchestrator
set -euo pipefail

usage() {
  cat <<'EOF'
qobeat-repos.sh - Generate catalog for qobeat repositories

This wrapper automatically defaults the owner to "qobeat" and routes data to
the standard data/qobeat/ location.

Usage:
  scripts/qobeat-repos.sh <repo-mask> [additional orchestrator args...]

Examples:
  scripts/qobeat-repos.sh '*' --type private --refresh-repo-list
  scripts/qobeat-repos.sh 'ados-*' --type public --parallel 5
EOF
}

if [[ $# -eq 0 || "$1" == "-h" || "$1" == "--help" ]]; then
  usage
  exit 1
fi

REPO_MASK="$1"
shift

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ORCHESTRATOR="$SCRIPT_DIR/github-catalog-orchestrator.sh"

echo "Executing catalog orchestrator for owner 'qobeat' with mask '$REPO_MASK'..."

"$ORCHESTRATOR" \
  --owner "qobeat" \
  --repos "$REPO_MASK" \
  "$@"