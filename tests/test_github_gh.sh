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

  rm -rf "$work"
}
