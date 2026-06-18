#!/usr/bin/env bash
# github-catalog-report.sh — pure-jq markdown report generator (no git/network)
set -euo pipefail

usage() {
  cat <<'EOF'
github-catalog-report.sh - generate Markdown report from JSONL catalog data

Options:
  --catalog PATH   Catalog JSONL (default: data/git-projects-catalog.jsonl)
  --commits PATH   Commits JSONL (default: data/git-projects-commits.jsonl)
  --output PATH    Output Markdown file (default: reports/latest.md)
  -h, --help       Show this help

EOF
}

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

CATALOG_JSONL="$REPO_ROOT/data/git-projects-catalog.jsonl"
COMMITS_JSONL="$REPO_ROOT/data/git-projects-commits.jsonl"
OUTPUT="$REPO_ROOT/reports/latest.md"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --catalog) CATALOG_JSONL="${2:?}"; shift 2 ;;
    --commits) COMMITS_JSONL="${2:?}"; shift 2 ;;
    --output)  OUTPUT="${2:?}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *)         fail "unknown option: $1" ;;
  esac
done

[[ -f "$CATALOG_JSONL" ]] || fail "catalog file not found: $CATALOG_JSONL"
[[ -s "$CATALOG_JSONL" ]] || fail "catalog file is empty: $CATALOG_JSONL"

mkdir -p "$(dirname -- "$OUTPUT")"

GENERATED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
REPO_COUNT=$(jq -rn '
  [inputs | select(.record_type == "repo_snapshot")]
  | group_by(.repo_slug) | length
' "$CATALOG_JSONL")

{
  cat <<EOF
# GitHub Catalog Report

**Generated:** $GENERATED_AT  
**Catalog:** \`$CATALOG_JSONL\`  
**Commits:** \`$COMMITS_JSONL\`  
**Repositories:** $REPO_COUNT

## Summary

| Repo | SHA | Last Commit | Key Files | Goal (excerpt) | Skipped |
|------|-----|-------------|-----------|----------------|---------|
EOF

  jq -rn '
    def latest_per_repo:
      [inputs | select(.record_type == "repo_snapshot")]
      | group_by(.repo_slug)
      | map(
          sort_by(.generated_at)
          | (map(select(.collection_skipped == false)) | if length > 0 then .[-1] else .[-1] end)
        );

    def goal_excerpt:
      (.goal.text // "—" | split("\n")[0] | if length > 80 then .[0:80] + "…" else . end);

    latest_per_repo
    | sort_by(.repo_slug)
    | .[]
    | "| \(.repo_slug) | `\(.head_commit_sha[0:7])` | \(.head_commit_at // "—") | \(.key_files_present | length) | \(goal_excerpt) | \(.collection_skipped) |"
  ' "$CATALOG_JSONL"

  echo ""
  echo "## Commit Activity"
  echo ""
  if [[ -f "$COMMITS_JSONL" && -s "$COMMITS_JSONL" ]]; then
    echo "| Repo | Commits | Latest |"
    echo "|------|---------|--------|"
    jq -rn '
      [inputs | select(.record_type == "commit")]
      | group_by(.repo_slug)
      | map({
          repo: .[0].repo_slug,
          count: length,
          latest: (sort_by(.committed_at) | last | .committed_at // "—")
        })
      | sort_by(.repo)
      | .[]
      | "| \(.repo) | \(.count) | \(.latest) |"
    ' "$COMMITS_JSONL"
  else
    echo "_No commit records found._"
  fi

  echo ""
  echo "## Repository Details"
  echo ""

  jq -rn '
    def latest_per_repo:
      [inputs | select(.record_type == "repo_snapshot")]
      | group_by(.repo_slug)
      | map(
          sort_by(.generated_at)
          | (map(select(.collection_skipped == false)) | if length > 0 then .[-1] else .[-1] end)
        );

    def field_text($f):
      if $f == null then "—" else $f.text end;

    latest_per_repo
    | sort_by(.repo_slug)
    | .[]
    | . as $r
    | [
        "### \($r.repo_slug)",
        "",
        "- **URL:** \($r.repo_url)",
        "- **Branch:** \($r.default_branch)",
        "- **HEAD SHA:** `\($r.head_commit_sha)`",
        "- **Key files:** \(if ($r.key_files_present | length) == 0 then "—" else ($r.key_files_present | join(", ")) end)",
        "",
        "#### Goal",
        "",
        field_text($r.goal),
        "",
        "#### Objectives",
        "",
        field_text($r.objectives),
        "",
        "#### Workflows",
        "",
        field_text($r.flows),
        "",
        "#### Requirements",
        "",
        field_text($r.requirements)
      ]
      + (if ($r.errors | length) > 0 then
          ["", "#### Errors", ""] + ($r.errors | map("- " + .))
        else [] end)
      + ["", "---", ""]
    | .[]
  ' "$CATALOG_JSONL"
} > "$OUTPUT"

line_count=$(wc -l < "$OUTPUT" | tr -d ' ')
(( line_count > 0 )) || fail "report generation produced empty output"

printf 'Wrote %s (%s lines)\n' "$OUTPUT" "$line_count"
