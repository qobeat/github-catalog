#!/usr/bin/env bash
# Unit tests for 777genius inventory refresh (offline mock gh)

make_777genius_mock_gh() {
  local mock_bin="$1"
  mkdir -p "$mock_bin"
  cat > "$mock_bin/gh" <<'MOCK'
#!/usr/bin/env bash
if [[ "$1" == "repo" && "$2" == "list" ]]; then
  owner="$3"
  visibility=""
  shift 3
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --visibility) visibility="$2"; shift 2 ;;
      --limit|--json) shift 2 ;;
      *) shift ;;
    esac
  done
  if [[ "$owner" != "777genius" ]]; then
    echo "unexpected owner: $owner" >&2
    exit 1
  fi
  if [[ "$visibility" == "public" || -z "$visibility" ]]; then
    printf '%s\n' '[{"name":"memo-stack","url":"https://github.com/777genius/memo-stack","visibility":"PUBLIC","defaultBranchRef":{"name":"main"}},{"name":"review-router","url":"https://github.com/777genius/review-router","visibility":"PUBLIC","defaultBranchRef":{"name":"main"}}]'
    exit 0
  fi
  if [[ "$visibility" == "private" ]]; then
    printf '%s\n' '[]'
    exit 0
  fi
  printf '%s\n' '[{"name":"memo-stack","url":"https://github.com/777genius/memo-stack","visibility":"PUBLIC","defaultBranchRef":{"name":"main"}},{"name":"secret-tool","url":"https://github.com/777genius/secret-tool","visibility":"PRIVATE","defaultBranchRef":{"name":"main"}}]'
  exit 0
fi
if [[ "$1" == "repo" && "$2" == "view" ]]; then
  target="$3"
  shift 3
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --json) shift 2 ;;
      *) shift ;;
    esac
  done
  case "$target" in
    777genius/memo-stack)
      printf '%s\n' '{"name":"memo-stack","url":"https://github.com/777genius/memo-stack","visibility":"PUBLIC","defaultBranchRef":{"name":"main"}}'
      exit 0
      ;;
    777genius/review-router)
      printf '%s\n' '{"name":"review-router","url":"https://github.com/777genius/review-router","visibility":"PUBLIC","defaultBranchRef":{"name":"main"}}'
      exit 0
      ;;
    777genius/secret-tool)
      printf '%s\n' '{"name":"secret-tool","url":"https://github.com/777genius/secret-tool","visibility":"PRIVATE","defaultBranchRef":{"name":"main"}}'
      exit 0
      ;;
  esac
  echo "repository not found: $target" >&2
  exit 1
fi
echo "unexpected gh call: $*" >&2
exit 1
MOCK
  chmod +x "$mock_bin/gh"
}

test_777genius_refresh_public_repos() {
  local work mock_bin data_dir out
  work="$(mktemp -d)"
  mock_bin="$work/bin"
  data_dir="$work/data"
  mkdir -p "$mock_bin" "$data_dir"
  make_777genius_mock_gh "$mock_bin"

  PATH="$mock_bin:$PATH" \
    "$REPO_ROOT/scripts/github-catalog-refresh.sh" \
      "777genius" \
      --public \
      --limit 10 \
      --data-dir "$data_dir"

  out="$data_dir/user-repositories.jsonl"
  [[ -f "$out" ]] || { echo "missing user-repositories.jsonl under $work" >&2; return 1; }

  local count
  count=$(jq -rn '[inputs | select(.record_type == "user_repository")] | length' "$out")
  assert_eq "2" "$count"

  assert_eq "777genius" "$(jq -r '.owner' "$out" | sort -u | head -1)"
  assert_eq "public" "$(jq -r 'select(.repo_slug=="memo-stack") | .visibility' "$out")"
  assert_eq "public" "$(jq -r 'select(.repo_slug=="review-router") | .visibility' "$out")"
  assert_eq "main" "$(jq -r 'select(.repo_slug=="memo-stack") | .default_branch' "$out")"

  rm -rf "$work"
}

test_777genius_refresh_single_public_repo() {
  local work mock_bin data_dir out
  work="$(mktemp -d)"
  mock_bin="$work/bin"
  data_dir="$work/data"
  mkdir -p "$mock_bin" "$data_dir"
  make_777genius_mock_gh "$mock_bin"

  PATH="$mock_bin:$PATH" \
    "$REPO_ROOT/scripts/github-catalog-refresh.sh" \
      "777genius/memo-stack" \
      --public \
      --data-dir "$data_dir"

  out="$data_dir/user-repositories.jsonl"
  [[ -f "$out" ]] || { echo "missing user-repositories.jsonl" >&2; return 1; }

  assert_eq "1" "$(jq -rn '[inputs | select(.record_type == "user_repository")] | length' "$out")"
  assert_eq "memo-stack" "$(jq -r '.repo_slug' "$out")"
  assert_eq "777genius" "$(jq -r '.owner' "$out")"
  assert_eq "public" "$(jq -r '.visibility' "$out")"

  rm -rf "$work"
}

test_777genius_refresh_accepts_github_url() {
  local work mock_bin data_dir out
  work="$(mktemp -d)"
  mock_bin="$work/bin"
  data_dir="$work/data"
  mkdir -p "$mock_bin" "$data_dir"
  make_777genius_mock_gh "$mock_bin"

  PATH="$mock_bin:$PATH" \
    "$REPO_ROOT/scripts/github-catalog-refresh.sh" \
      "https://github.com/777genius" \
      --public \
      --limit 10 \
      --data-dir "$data_dir"

  out="$data_dir/user-repositories.jsonl"
  [[ -f "$out" ]] || { echo "missing user-repositories.jsonl" >&2; return 1; }

  assert_eq "2" "$(jq -rn '[inputs | select(.record_type == "user_repository")] | length' "$out")"

  rm -rf "$work"
}

test_777genius_refresh_public_filter_rejects_private_repo() {
  local work mock_bin
  work="$(mktemp -d)"
  mock_bin="$work/bin"
  make_777genius_mock_gh "$mock_bin"

  if PATH="$mock_bin:$PATH" \
    "$REPO_ROOT/scripts/github-catalog-refresh.sh" \
      "777genius/secret-tool" \
      --public 2>/dev/null; then
    rm -rf "$work"
    echo "expected failure for private repo with --public" >&2
    return 1
  fi

  rm -rf "$work"
}

test_777genius_get_repo_writes_jsonl() {
  local work mock_bin data_dir out
  work="$(mktemp -d)"
  mock_bin="$work/bin"
  data_dir="$work/data"
  mkdir -p "$mock_bin" "$data_dir"
  make_777genius_mock_gh "$mock_bin"

  PATH="$mock_bin:$PATH" \
    "$REPO_ROOT/scripts/github-gh.sh" get-repo \
      --owner "777genius" \
      --repo "review-router" \
      --type "public" \
      --report-id "2026-06-18T12:00:00Z" \
      --data-dir "$data_dir"

  out="$data_dir/user-repositories.jsonl"
  [[ -f "$out" ]] || { echo "missing $out" >&2; return 1; }

  assert_eq "user_repository" "$(jq -r '.record_type' "$out")"
  assert_eq "review-router" "$(jq -r '.repo_slug' "$out")"
  assert_eq "777genius" "$(jq -r '.owner' "$out")"
  assert_eq "public" "$(jq -r '.visibility' "$out")"

  rm -rf "$work"
}
