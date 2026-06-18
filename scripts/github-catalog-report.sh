#!/usr/bin/env bash
# scripts/github-catalog-report.sh - Generate markdown reports using pure jq
set -euo pipefail

usage() {
  cat <<'EOF'
github-catalog-report.sh - Generate Markdown report from catalog JSONL

Usage:
  scripts/github-catalog-report.sh --owner NAME [options]

Options:
  --owner NAME          Owner name (required; used in report title and default paths)
  --data-dir DIR        JSONL directory (default: data/<owner>)
  --catalog FILE        Catalog JSONL path (overrides --data-dir)
  --commits FILE        Commits JSONL path (overrides --data-dir)
  --output FILE         Output markdown path (default: reports/<owner>/latest.md)
EOF
}

OWNER=""
DATA_DIR=""
CATALOG_JSONL=""
COMMITS_JSONL=""
OUT_MD=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --owner)   OWNER="${2:?}"; shift 2 ;;
    --data-dir) DATA_DIR="${2:?}"; shift 2 ;;
    --catalog) CATALOG_JSONL="${2:?}"; shift 2 ;;
    --commits) COMMITS_JSONL="${2:?}"; shift 2 ;;
    --output)  OUT_MD="${2:?}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: unknown option $1" >&2; exit 1 ;;
  esac
done

[[ -n "$OWNER" ]] || { echo "ERROR: --owner is required" >&2; exit 1; }

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

if [[ -z "$DATA_DIR" && -z "$CATALOG_JSONL" ]]; then
  DATA_DIR="$REPO_ROOT/data/$OWNER"
fi

if [[ -z "$CATALOG_JSONL" ]]; then
  CATALOG_JSONL="$DATA_DIR/git-projects-catalog.jsonl"
fi

if [[ -z "$COMMITS_JSONL" ]]; then
  COMMITS_JSONL="$DATA_DIR/git-projects-commits.jsonl"
fi

if [[ -z "$OUT_MD" ]]; then
  OUT_MD="$REPO_ROOT/reports/$OWNER/latest.md"
fi

[[ -f "$CATALOG_JSONL" ]] || { echo "ERROR: Catalog not found at $CATALOG_JSONL" >&2; exit 1; }

mkdir -p "$(dirname -- "$OUT_MD")"

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