#!/usr/bin/env bash
# scripts/github-catalog-report.sh - Generate markdown reports using pure jq
set -euo pipefail

usage() {
  cat <<'EOF'
github-catalog-report.sh - Generate Markdown report from catalog JSONL

Usage:
  scripts/github-catalog-report.sh --owner NAME
EOF
}

OWNER=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --owner) OWNER="${2:?}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: unknown option $1" >&2; exit 1 ;;
  esac
done

[[ -n "$OWNER" ]] || { echo "ERROR: --owner is required" >&2; exit 1; }

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

DATA_DIR="$REPO_ROOT/data/$OWNER"
REPORT_DIR="$REPO_ROOT/reports/$OWNER"
CATALOG_JSONL="$DATA_DIR/git-projects-catalog.jsonl"
COMMITS_JSONL="$DATA_DIR/git-projects-commits.jsonl"
OUT_MD="$REPORT_DIR/latest.md"

[[ -f "$CATALOG_JSONL" ]] || { echo "ERROR: Catalog not found at $CATALOG_JSONL" >&2; exit 1; }

mkdir -p "$REPORT_DIR"

# Generate the Markdown directly via jq
jq -rn --arg owner "$OWNER" --arg date "$(date -u +"%Y-%m-%d %H:%M UTC")" '
  [inputs | select(.record_type == "repo_snapshot")]
  | group_by(.repo_slug)
  | map(sort_by(.generated_at) | last)
  | sort_by(.repo_slug)
  | (
      "# GitHub Catalog Report: \($owner)\n" +
      "_Generated: \($date)_\n\n" +
      "## Repository Summary\n\n" +
      "| Repository | SHA | Last Commit | Goal |\n" +
      "|---|---|---|---|\n"
    ),
    (
      .[] | 
      "| **\(.repo_slug)** " +
      "| `\(.head_commit_sha[0:7] // "-------")` " +
      "| \(.head_commit_at // "Unknown") " +
      "| \((.goal.text // "Not documented") | split("\n")[0] | .[0:80]) |\n"
    ),
    "\n## Detailed Semantics\n\n",
    (
      .[] | select(.goal != null or .objectives != null or .requirements != null) |
      "### \(.repo_slug)\n\n" +
      (if .goal != null then "**Goal:**\n> \(.goal.text)\n\n" else "" end) +
      (if .objectives != null then "**Objectives:**\n> \(.objectives.text)\n\n" else "" end) +
      (if .requirements != null then "**Requirements:**\n> \(.requirements.text)\n\n" else "" end)
    )
' "$CATALOG_JSONL" > "$OUT_MD"

echo "Report generated: $OUT_MD"