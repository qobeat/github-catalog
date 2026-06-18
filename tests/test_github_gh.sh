#!/usr/bin/env bash
# Unit tests for github-gh.sh list-repos (offline mock gh)

test_list_repos_writes_jsonl() {
  local work mock_bin data_dir out
  work="$(mktemp -d)"
  mock_bin="$work/bin"
  data_dir="$work/data"
  mkdir -p "$mock_bin" "$data_dir"

  cat > "$mock_bin/gh" <<'MOCK'
#!/usr/bin/env bash
if [[ "$1" == "repo" && "$2" == "list" ]]; then
  printf '%s\n' '[{"name":"ados-framework","url":"https://github.com/qobeat/ados-framework","visibility":"PRIVATE","defaultBranchRef":{"name":"main"}}]'
  exit 0
fi
echo "unexpected gh call: $*" >&2
exit 1
MOCK
  chmod +x "$mock_bin/gh"

  PATH="$mock_bin:$PATH" \
    "$REPO_ROOT/scripts/github-gh.sh" list-repos \
      --owner "qobeat" \
      --type "private" \
      --report-id "2026-06-18T00:00:00Z" \
      --data-dir "$data_dir" \
      --limit 10

  out="$data_dir/user-repositories.jsonl"
  [[ -f "$out" ]] || { echo "missing $out" >&2; return 1; }

  assert_eq "user_repository" "$(jq -r '.record_type' "$out")"
  assert_eq "ados-framework" "$(jq -r '.repo_slug' "$out")"
  assert_eq "qobeat" "$(jq -r '.owner' "$out")"
  assert_eq "private" "$(jq -r '.visibility' "$out")"
  assert_eq "main" "$(jq -r '.default_branch' "$out")"
  assert_eq "2026-06-18T00:00:00Z" "$(jq -r '.report_id' "$out")"
  assert_eq "active" "$(jq -r '.status' "$out")"

  rm -rf "$work"
}

test_list_repos_all_visibility() {
  local work mock_bin data_dir out count
  work="$(mktemp -d)"
  mock_bin="$work/bin"
  data_dir="$work/data"
  mkdir -p "$mock_bin" "$data_dir"

  cat > "$mock_bin/gh" <<'MOCK'
#!/usr/bin/env bash
if [[ "$1" == "repo" && "$2" == "list" ]]; then
  [[ "$*" != *"--visibility"* ]] || { echo "unexpected visibility flag: $*" >&2; exit 1; }
  printf '%s\n' '[{"name":"pub","url":"https://github.com/o/pub","visibility":"PUBLIC","defaultBranchRef":{"name":"main"}},{"name":"priv","url":"https://github.com/o/priv","visibility":"PRIVATE","defaultBranchRef":{"name":"dev"}}]'
  exit 0
fi
echo "unexpected gh call: $*" >&2
exit 1
MOCK
  chmod +x "$mock_bin/gh"

  PATH="$mock_bin:$PATH" \
    "$REPO_ROOT/scripts/github-gh.sh" list-repos \
      --owner "o" \
      --type "all" \
      --report-id "run-1" \
      --data-dir "$data_dir"

  out="$data_dir/user-repositories.jsonl"
  count=$(jq -rn '[inputs | select(.record_type == "user_repository")] | length' "$out")
  assert_eq "2" "$count"

  rm -rf "$work"
}

test_list_repos_tombstones_missing_repo() {
  local work mock_bin data_dir out tombstones tombstone_file
  work="$(mktemp -d)"
  mock_bin="$work/bin"
  data_dir="$work/data"
  tombstone_file="$work/tombstones.txt"
  mkdir -p "$mock_bin" "$data_dir"

  cat > "$data_dir/user-repositories.jsonl" <<'JSONL'
{"schema_version":"1.2.0","record_type":"user_repository","report_id":"old-run","generated_at":"2026-06-01T00:00:00Z","owner":"o","repo_slug":"gone","repo_url":"https://github.com/o/gone","visibility":"public","default_branch":"main","status":"active"}
{"schema_version":"1.2.0","record_type":"user_repository","report_id":"old-run","generated_at":"2026-06-01T00:00:00Z","owner":"o","repo_slug":"kept","repo_url":"https://github.com/o/kept","visibility":"public","default_branch":"main","status":"active"}
JSONL

  cat > "$mock_bin/gh" <<'MOCK'
#!/usr/bin/env bash
if [[ "$1" == "repo" && "$2" == "list" ]]; then
  printf '%s\n' '[{"name":"kept","url":"https://github.com/o/kept","visibility":"PUBLIC","defaultBranchRef":{"name":"main"}}]'
  exit 0
fi
echo "unexpected gh call: $*" >&2
exit 1
MOCK
  chmod +x "$mock_bin/gh"

  PATH="$mock_bin:$PATH" \
    "$REPO_ROOT/scripts/github-gh.sh" list-repos \
      --owner "o" \
      --type "all" \
      --report-id "new-run" \
      --data-dir "$data_dir" \
      --tombstones-file "$tombstone_file"

  out="$data_dir/user-repositories.jsonl"
  tombstones=$(jq -rn '[inputs | select(.record_type == "user_repository" and .status == "deleted")] | length' "$out")
  assert_eq "1" "$tombstones"
  assert_eq "gone" "$(jq -rn '[inputs | select(.status == "deleted")] | .[0].repo_slug' "$out")"
  grep -qx 'gone' "$tombstone_file" || return 1

  rm -rf "$work"
}
