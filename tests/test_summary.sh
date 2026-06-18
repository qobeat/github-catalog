#!/usr/bin/env bash
# tests/test_summary.sh - post-sync stdout summary line
set -euo pipefail

test_summary_jq_aggregation() {
  local work owner out stats
  work="$(mktemp -d)"
  owner="_sum_test"
  mkdir -p "$work/data/$owner"
  cat > "$work/data/$owner/git-projects-catalog.jsonl" <<'JSONL'
{"schema_version":"1.2.0","record_type":"repo_snapshot","report_id":"2026-06-17T12:00:00Z","generated_at":"2026-06-17T12:00:01Z","collection_skipped":false,"status":"active","owner":"_sum_test","repo_slug":"a","errors":[]}
{"schema_version":"1.2.0","record_type":"repo_snapshot","report_id":"2026-06-17T12:00:00Z","generated_at":"2026-06-17T12:00:02Z","collection_skipped":true,"status":"active","owner":"_sum_test","repo_slug":"b","errors":[]}
JSONL
  cat > "$work/data/$owner/git-projects-commits.jsonl" <<'JSONL'
{"schema_version":"1.0.0","record_type":"commit","report_id":"2026-06-17T12:00:00Z","repo_slug":"a","sha":"sha1","committed_at":"2026-06-17T10:00:00Z"}
JSONL

  stats=$(jq -rn \
    --arg rid "2026-06-17T12:00:00Z" \
    --argjson failures 0 \
    --argjson catalog "$(jq -s '.' "$work/data/$owner/git-projects-catalog.jsonl")" \
    --argjson commits "$(jq -s '.' "$work/data/$owner/git-projects-commits.jsonl")" \
    '
    ($catalog // []) as $cat |
    ($commits // []) as $com |
    ($cat | map(select(.record_type == "repo_snapshot" and .report_id == $rid))) as $snaps |
    {
      collected: ($snaps | map(select(.collection_skipped == false and (.errors | length) == 0)) | length),
      skipped: ($snaps | map(select(.collection_skipped == true)) | length),
      failed: $failures,
      new_commits: ($com | map(select(.record_type == "commit" and .report_id == $rid)) | length)
    }
    ')

  assert_eq "1" "$(jq -r '.collected' <<< "$stats")"
  assert_eq "1" "$(jq -r '.skipped' <<< "$stats")"
  assert_eq "1" "$(jq -r '.new_commits' <<< "$stats")"

  out="$(printf 'Synced %d repos for %s: %s collected, %s skipped (unchanged), %s failed, %s new commits.\nNext: ./github-catalog report %s\n' \
    2 "$owner" \
    "$(jq -r '.collected' <<< "$stats")" \
    "$(jq -r '.skipped' <<< "$stats")" \
    "$(jq -r '.failed' <<< "$stats")" \
    "$(jq -r '.new_commits' <<< "$stats")" \
    "$owner")"
  grep -q 'Synced 2 repos for _sum_test' <<< "$out" || return 1
  grep -q 'Next: ./github-catalog report _sum_test' <<< "$out" || return 1
  rm -rf "$work"
}
