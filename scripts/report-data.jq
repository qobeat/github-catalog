# report-data.jq — aggregate catalog + commits JSONL into a single report object
# Usage: { cat catalog.jsonl; cat commits.jsonl; } | jq -rn --arg owner NAME --arg date DATE -f report-data.jq

def repo_status: (.status // "active");

def latest_repos($catalog):
  $catalog
  | map(select(.record_type == "repo_snapshot"))
  | group_by(.repo_slug)
  | map(sort_by(.generated_at) | last)
  | sort_by(.repo_slug);

def latest_run($catalog):
  $catalog
  | map(select(.record_type == "run"))
  | sort_by(.generated_at)
  | last;

def commit_activity($commits; $statuses):
  if ($commits | length) == 0 then []
  else
    $commits
    | group_by(.repo_slug)
    | map({
        repo_slug: .[0].repo_slug,
        repo_label: (
          if ($statuses[.[0].repo_slug] // "active") == "deleted"
          then "\(.[0].repo_slug) [deleted]"
          else .[0].repo_slug
          end
        ),
        commits_recorded: length,
        latest_commit: (sort_by(.committed_at) | last | .committed_at)
      })
    | sort_by(.repo_slug)
  end;

def semantics($repos):
  $repos
  | map(select(.goal != null or .objectives != null or .flows != null or .requirements != null))
  | map({
      repo_slug,
      repo_url,
      status: repo_status,
      default_branch,
      created_at,
      key_files_present,
      goal,
      objectives,
      flows,
      requirements
    });

def collection_errors($repos):
  $repos
  | map(select(((.errors // []) | length) > 0 and (.status // "active") != "deleted"))
  | map({repo_slug, errors: (.errors // [])});

[inputs] as $all |
($all | map(select(.record_type != "commit"))) as $catalog |
($all | map(select(.record_type == "commit"))) as $commits |
($catalog | latest_repos(.)) as $repos |
($catalog | latest_run(.)) as $run |
($repos | map({key: .repo_slug, value: repo_status}) | from_entries) as $statuses |
{
  owner: $owner,
  generated_at: $date,
  overview: {
    repos_cataloged: ($repos | length),
    repos_deleted: ($repos | map(select(repo_status == "deleted")) | length),
    repos_skipped_last_snapshot: ($repos | map(select(.collection_skipped)) | length),
    last_run: (
      if $run == null then null
      else {
        report_id: $run.report_id,
        generated_at: $run.generated_at,
        repos_glob: $run.repos_glob,
        visibility_filter: $run.visibility_filter,
        repos_total: $run.repos_total,
        repos_completed: $run.repos_completed,
        failures: $run.failures,
        parallel: $run.parallel
      }
      end
    )
  },
  repositories: (
    $repos
    | map({
        repo_slug,
        repo_url,
        status: repo_status,
        collection_skipped: (.collection_skipped // false),
        default_branch,
        head_commit_sha,
        head_commit_at,
        key_files_count: (.key_files_present | length),
        goal_excerpt: ((.goal.text // "Not documented") | split("\n")[0] | .[0:80])
      })
  ),
  commit_activity: commit_activity($commits; $statuses),
  semantics: semantics($repos),
  errors: collection_errors($repos)
}
