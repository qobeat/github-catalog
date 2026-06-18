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
  --output FILE         Output markdown path (default: reports/<owner>/report-<timestamp>.md + latest.md symlink)
EOF
}

# Fingerprint report body, stripping lines that change per generation or sync run.
report_content_fingerprint() {
  sed -E \
    -e '/^_Generated: .*_$/d' \
    -e '/^- \*\*Last sync run:\*\*/d' \
    "$1" | sha256sum | awk '{print $1}'
}

catalog_missing_error() {
  local owner="$1" catalog_path="$2" data_dir="$3"
  local inventory_path="$data_dir/user-repositories.jsonl"

  cat >&2 <<EOF
ERROR: Catalog not found at $catalog_path

The report command reads catalog snapshots from sync; it does not fetch from GitHub.

To create the missing catalog, run sync first:

  ./github-catalog sync $owner '*' --refresh   # first run: inventory + catalog
  ./github-catalog report $owner

Other useful sync forms:
  ./github-catalog sync $owner 'prefix-*'      # catalog a subset (uses cached inventory)
  ./github-catalog sync $owner my-repo --git-host <alias>   # single repo via SSH alias

Prerequisites: gh auth login (for inventory refresh), git, jq.
See README.md — "Getting started from zero".
EOF

  if [[ -f "$inventory_path" ]]; then
    cat >&2 <<EOF

Note: inventory exists at $inventory_path — sync will reuse it (no --refresh needed).
EOF
  elif [[ ! -d "$data_dir" ]] || [[ -z "$(ls -A "$data_dir" 2>/dev/null || true)" ]]; then
    cat >&2 <<EOF

Note: no local data for owner '$owner' yet — start with sync --refresh.
EOF
  fi
}

OWNER=""
DATA_DIR=""
CATALOG_JSONL=""
COMMITS_JSONL=""
OUT_MD=""
UPDATE_LATEST_SYMLINK=0

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
  REPORT_TS="$(date -u +%Y-%m-%dT%H-%M-%SZ)"
  REPORT_DIR="$REPO_ROOT/reports/$OWNER"
  OUT_MD="$REPORT_DIR/report-${REPORT_TS}.md"
  REPORT_BASENAME="report-${REPORT_TS}.md"
  UPDATE_LATEST_SYMLINK=1
fi

if [[ ! -f "$CATALOG_JSONL" ]]; then
  catalog_missing_error "$OWNER" "$CATALOG_JSONL" "$DATA_DIR"
  exit 1
fi

mkdir -p "$(dirname -- "$OUT_MD")"
REPORT_DATE="$(date -u +"%Y-%m-%d %H:%M UTC")"

WRITE_TARGET="$OUT_MD"
TEMP_REPORT=""
if (( UPDATE_LATEST_SYMLINK == 1 )); then
  TEMP_REPORT="$(mktemp)"
  WRITE_TARGET="$TEMP_REPORT"
fi

# --- Section A + B: overview and repository summary ---
jq -rn \
  --arg owner "$OWNER" \
  --arg date "$REPORT_DATE" \
  '
  def repo_status: .status // "active";
  def deleted_suffix: if repo_status == "deleted" then " [deleted]" else "" end;
  def skipped_suffix: if .collection_skipped then "*" else "" end;
  [inputs] as $all |
  ($all
    | map(select(.record_type == "repo_snapshot"))
    | group_by(.repo_slug)
    | map(sort_by(.generated_at) | last)
    | sort_by(.repo_slug)) as $repos |
  ($all
    | map(select(.record_type == "run"))
    | sort_by(.generated_at)
    | last) as $run |
  (
    "# GitHub Catalog Report: \($owner)\n" +
    "_Generated: \($date)_\n\n" +
    "## Catalog Overview\n\n" +
    "- **Repositories cataloged:** \($repos | length)\n" +
    "- **Repositories deleted:** \($repos | map(select(repo_status == "deleted")) | length)\n" +
    (if $run != null then
      "- **Last sync run:** \($run.report_id) — glob `\($run.repos_glob)`, " +
      "\($run.repos_completed)/\($run.repos_total) completed, \($run.failures) failures, parallel \($run.parallel)\n"
    else "" end) +
    "- **Skipped on last snapshot:** \($repos | map(select(.collection_skipped)) | length) repos (HEAD unchanged)\n\n" +
    "## Repository Summary\n\n" +
    "| Repository | Branch | SHA | Last Commit | Key Files | Goal (excerpt) |\n" +
    "|---|---|---|---|---|---|\n"
  ),
  (
    $repos[] |
    (if (.repo_url | startswith("https://")) then
      "[\(.repo_slug)\(skipped_suffix)\(deleted_suffix)](\(.repo_url))"
    else
      "**\(.repo_slug)\(skipped_suffix)\(deleted_suffix)**"
    end) as $repo_cell |
    "| \($repo_cell) | \(.default_branch // "—") | `\(.head_commit_sha[0:7] // "-------")` | " +
    "\(.head_commit_at // "Unknown") | \(.key_files_present | length) | " +
    "\((.goal.text // "Not documented") | split("\n")[0] | .[0:80]) |\n"
  )
' "$CATALOG_JSONL" > "$WRITE_TARGET"

# --- Section C: commit activity (optional) ---
{
  echo ""
  if [[ -f "$COMMITS_JSONL" ]] && [[ -s "$COMMITS_JSONL" ]]; then
    status_map=$(jq -rn '
      [inputs | select(.record_type == "repo_snapshot")]
      | group_by(.repo_slug)
      | map({
          key: .[0].repo_slug,
          value: (sort_by(.generated_at) | last | .status // "active")
        })
      | from_entries
    ' "$CATALOG_JSONL")
    jq -rn \
      --argjson statuses "$status_map" \
      '
      "## Commit Activity\n\n" +
      "| Repository | Commits recorded | Latest commit |\n" +
      "|---|---|---|\n",
      (
        [inputs | select(.record_type == "commit")]
        | group_by(.repo_slug)
        | map({
            repo: .[0].repo_slug,
            count: length,
            latest: (sort_by(.committed_at) | last | .committed_at)
          })
        | sort_by(.repo)
        | .[]
        | (if ($statuses[.repo] // "active") == "deleted" then "\(.repo) [deleted]" else .repo end) as $label |
        "| \($label) | \(.count) | \(.latest // "Unknown") |\n"
      )
    ' "$COMMITS_JSONL"
  else
    echo "_Commit history not available — run sync to populate \`git-projects-commits.jsonl\`._"
  fi
} >> "$WRITE_TARGET"

# --- Section D: detailed semantics ---
{
  echo ""
  echo "## Detailed Semantics"
  echo ""
  jq -rn '
    def repo_status: .status // "active";
    def deleted_suffix: if repo_status == "deleted" then " [deleted]" else "" end;
    [inputs
      | select(.record_type == "repo_snapshot")
    ]
    | group_by(.repo_slug)
    | map(sort_by(.generated_at) | last)
    | sort_by(.repo_slug)
    | map(select(.goal != null or .objectives != null or .flows != null or .requirements != null))
    | if length == 0 then
      "_No documented goal, objectives, flows, or requirements found._\n"
    else
      .[] |
      (if (.repo_url | startswith("https://")) then
        "### [\(.repo_slug)\(deleted_suffix)](\(.repo_url))\n\n"
      else
        "### \(.repo_slug)\(deleted_suffix)\n\n"
      end) +
      "- **Branch:** \(.default_branch // "—")\n" +
      (if repo_status == "deleted" then "- **Status:** deleted\n" else "" end) +
      (if .created_at then "- **Created:** \(.created_at)\n" else "" end) +
      (if (.key_files_present | length) > 0 then
        "- **Key files:** \(.key_files_present | join(", "))\n"
      else "" end) +
      (if (.repo_url != null and (.repo_url | startswith("https://") | not)) then
        "- **URL:** \(.repo_url)\n"
      else "" end) +
      "\n" +
      (if .goal != null then
        "**Goal:**\n_from `\(.goal.source_file)` § `\(.goal.source_heading)`_\n\n> \(.goal.text)\n\n"
      else "" end) +
      (if .objectives != null then
        "**Objectives:**\n_from `\(.objectives.source_file)` § `\(.objectives.source_heading)`_\n\n> \(.objectives.text)\n\n"
      else "" end) +
      (if .flows != null then
        "**Flows:**\n_from `\(.flows.source_file)` § `\(.flows.source_heading)`_\n\n> \(.flows.text)\n\n"
      else "" end) +
      (if .requirements != null then
        "**Requirements:**\n_from `\(.requirements.source_file)` § `\(.requirements.source_heading)`_\n\n> \(.requirements.text)\n\n"
      else "" end)
    end
  ' "$CATALOG_JSONL"
} >> "$WRITE_TARGET"

# --- Section E: collection errors (omit when empty) ---
jq -rn '
  def repo_status: .status // "active";
  [inputs | select(.record_type == "repo_snapshot")]
  | group_by(.repo_slug)
  | map(sort_by(.generated_at) | last)
  | map(select(.errors | length > 0 and repo_status != "deleted"))
  | if length == 0 then empty
    else
      "\n## Collection Errors\n\n" +
      "| Repository | Errors |\n" +
      "|---|---|\n",
      (.[] | "| \(.repo_slug) | \(.errors | join("; ")) |\n")
    end
' "$CATALOG_JSONL" >> "$WRITE_TARGET"

find_matching_report() {
  local report_dir="$1" fingerprint="$2" f fp
  for f in "$report_dir"/report-*.md; do
    [[ -f "$f" ]] || continue
    fp="$(report_content_fingerprint "$f")"
    if [[ "$fp" == "$fingerprint" ]]; then
      printf '%s\n' "$f"
      return 0
    fi
  done
  return 1
}

if (( UPDATE_LATEST_SYMLINK == 1 )); then
  LATEST_LINK="$REPORT_DIR/latest.md"
  NEW_FP="$(report_content_fingerprint "$TEMP_REPORT")"
  MATCHING_REPORT=""

  if [[ -L "$LATEST_LINK" ]] || [[ -f "$LATEST_LINK" ]]; then
    LATEST_TARGET="$REPORT_DIR/$(readlink "$LATEST_LINK" 2>/dev/null || basename "$LATEST_LINK")"
    if [[ -f "$LATEST_TARGET" ]]; then
      OLD_FP="$(report_content_fingerprint "$LATEST_TARGET")"
      if [[ "$NEW_FP" == "$OLD_FP" ]]; then
        MATCHING_REPORT="$LATEST_TARGET"
      fi
    fi
  fi

  if [[ -z "$MATCHING_REPORT" ]]; then
    MATCHING_REPORT="$(find_matching_report "$REPORT_DIR" "$NEW_FP" || true)"
  fi

  if [[ -n "$MATCHING_REPORT" ]]; then
    rm -f "$TEMP_REPORT"
    ln -sfn "$(basename -- "$MATCHING_REPORT")" "$LATEST_LINK"
    echo "Report unchanged: $LATEST_LINK"
    exit 0
  fi

  mv "$TEMP_REPORT" "$OUT_MD"
  ln -sfn "$REPORT_BASENAME" "$LATEST_LINK"
  echo "Report generated: $OUT_MD"
  echo "Latest report: $LATEST_LINK"
else
  echo "Report generated: $OUT_MD"
fi
