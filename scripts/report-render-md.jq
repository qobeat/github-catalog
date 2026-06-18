#!/usr/bin/env bash
# scripts/report-render-md.jq — render report JSON object as Markdown
# Usage: jq -r -f report-render-md.jq < report.json

def repo_link($r):
  if ($r.repo_url | startswith("https://")) then
    "[\($r.repo_slug)\(if $r.collection_skipped then "*" else "" end)\(if $r.status == "deleted" then " [deleted]" else "" end)](\($r.repo_url))"
  else
    "**\($r.repo_slug)\(if $r.collection_skipped then "*" else "" end)\(if $r.status == "deleted" then " [deleted]" else "" end)**"
  end;

"# GitHub Catalog Report: \(.owner)\n" +
"_Generated: \(.generated_at)_\n\n" +
"## Catalog Overview\n\n" +
"- **Repositories cataloged:** \(.overview.repos_cataloged)\n" +
"- **Repositories deleted:** \(.overview.repos_deleted)\n" +
(if .overview.last_run != null then
  "- **Last sync run:** \(.overview.last_run.report_id) — glob `\(.overview.last_run.repos_glob)`, " +
  "\(.overview.last_run.repos_completed)/\(.overview.last_run.repos_total) completed, " +
  "\(.overview.last_run.failures) failures, parallel \(.overview.last_run.parallel)\n"
else "" end) +
"- **Skipped on last snapshot:** \(.overview.repos_skipped_last_snapshot) repos (HEAD unchanged)\n\n" +
"## Repository Summary\n\n" +
"| Repository | Branch | SHA | Last Commit | Key Files | Goal (excerpt) |\n" +
"|---|---|---|---|---|---|\n" +
(
  .repositories[]
  | "| \(repo_link(.)) | \(.default_branch // "—") | `\(.head_commit_sha[0:7] // "-------")` | " +
    "\(.head_commit_at // "Unknown") | \(.key_files_count) | \(.goal_excerpt) |\n"
) +
"\n" +
(if (.commit_activity | length) > 0 then
  "## Commit Activity\n\n" +
  "| Repository | Commits recorded | Latest commit |\n" +
  "|---|---|---|\n" +
  (.commit_activity[]
    | "| \(.repo_label) | \(.commits_recorded) | \(.latest_commit // "Unknown") |\n")
else
  "_Commit history not available — run sync to populate `git-projects-commits.jsonl`._\n"
end) +
"\n## Detailed Semantics\n\n" +
(if (.semantics | length) == 0 then
  "_No documented goal, objectives, flows, or requirements found._\n"
else
  .semantics[]
  | (
      if (.repo_url | startswith("https://")) then
        "### [\(.repo_slug)\(if .status == "deleted" then " [deleted]" else "" end)](\(.repo_url))\n\n"
      else
        "### \(.repo_slug)\(if .status == "deleted" then " [deleted]" else "" end)\n\n"
      end
    ) +
    "- **Branch:** \(.default_branch // "—")\n" +
    (if .status == "deleted" then "- **Status:** deleted\n" else "" end) +
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
end) +
(if (.errors | length) > 0 then
  "\n## Collection Errors\n\n" +
  "| Repository | Errors |\n" +
  "|---|---|\n" +
  (.errors[] | "| \(.repo_slug) | \(.errors | join("; ")) |\n")
else "" end)
