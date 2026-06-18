#!/usr/bin/env bash
# scripts/github-catalog-report.sh - Generate markdown or JSON reports using pure jq
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=scripts/github-catalog-lib.sh
source "$SCRIPT_DIR/github-catalog-lib.sh"

usage() {
  cat <<'EOF'
github-catalog-report.sh - Generate report from catalog JSONL

Usage:
  scripts/github-catalog-report.sh --owner NAME [options]

Options:
  --owner NAME          Owner name (required; used in report title and default paths)
  --format md|json      Output format (default: md)
  --data-dir DIR        JSONL directory (default: data/<owner>)
  --catalog FILE        Catalog JSONL path (overrides --data-dir)
  --commits FILE        Commits JSONL path (overrides --data-dir)
  --output FILE         Output path (md: default reports/<owner>/report-<ts>.md; json: stdout)
  -h, --help            Show this help
EOF
}

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

build_report_json() {
  local owner="$1" date="$2" catalog="$3" commits="$4"
  {
    cat "$catalog"
    if [[ -f "$commits" ]] && [[ -s "$commits" ]]; then
      cat "$commits"
    fi
  } | jq -rn \
    --arg owner "$owner" \
    --arg date "$date" \
    -f "$SCRIPT_DIR/report-data.jq"
}

render_report_md() {
  jq -r -f "$SCRIPT_DIR/report-render-md.jq"
}

OWNER=""
DATA_DIR=""
CATALOG_JSONL=""
COMMITS_JSONL=""
OUT_MD=""
FORMAT="md"
UPDATE_LATEST_SYMLINK=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --owner)   OWNER="${2:?}"; shift 2 ;;
    --format)  FORMAT="${2:?}"; shift 2 ;;
    --data-dir) DATA_DIR="${2:?}"; shift 2 ;;
    --catalog) CATALOG_JSONL="${2:?}"; shift 2 ;;
    --commits) COMMITS_JSONL="${2:?}"; shift 2 ;;
    --output)  OUT_MD="${2:?}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) gc_exit_usage "unknown option $1" ;;
  esac
done

[[ -n "$OWNER" ]] || gc_exit_usage "--owner is required"
[[ "$FORMAT" == "md" || "$FORMAT" == "json" ]] || gc_exit_usage "--format must be md or json"

if [[ -z "$DATA_DIR" && -z "$CATALOG_JSONL" ]]; then
  DATA_DIR="$REPO_ROOT/data/$OWNER"
fi

if [[ -z "$CATALOG_JSONL" ]]; then
  CATALOG_JSONL="$DATA_DIR/git-projects-catalog.jsonl"
fi

if [[ -z "$COMMITS_JSONL" ]]; then
  COMMITS_JSONL="$DATA_DIR/git-projects-commits.jsonl"
fi

if [[ ! -f "$CATALOG_JSONL" ]]; then
  catalog_missing_error "$OWNER" "$CATALOG_JSONL" "$DATA_DIR"
  gc_exit_precond "catalog not found"
fi

REPORT_DATE="$(date -u +"%Y-%m-%d %H:%M UTC")"
REPORT_JSON="$(build_report_json "$OWNER" "$REPORT_DATE" "$CATALOG_JSONL" "$COMMITS_JSONL")"

if [[ "$FORMAT" == "json" ]]; then
  if [[ -n "$OUT_MD" ]]; then
    printf '%s\n' "$REPORT_JSON" > "$OUT_MD"
    echo "Report JSON written: $OUT_MD"
  else
    printf '%s\n' "$REPORT_JSON"
  fi
  exit 0
fi

if [[ -z "$OUT_MD" ]]; then
  REPORT_TS="$(date -u +%Y-%m-%dT%H-%M-%SZ)"
  REPORT_DIR="$REPO_ROOT/reports/$OWNER"
  OUT_MD="$REPORT_DIR/report-${REPORT_TS}.md"
  REPORT_BASENAME="report-${REPORT_TS}.md"
  UPDATE_LATEST_SYMLINK=1
fi

mkdir -p "$(dirname -- "$OUT_MD")"

WRITE_TARGET="$OUT_MD"
TEMP_REPORT=""
if (( UPDATE_LATEST_SYMLINK == 1 )); then
  TEMP_REPORT="$(mktemp)"
  WRITE_TARGET="$TEMP_REPORT"
fi

printf '%s\n' "$REPORT_JSON" | render_report_md > "$WRITE_TARGET"

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
