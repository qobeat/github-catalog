#!/usr/bin/env bash
# Unit tests for orchestrator helpers

normalize_owner() {
  local o="$1"
  o="${o#https://}"
  o="${o#http://}"
  o="${o#www.}"
  o="${o#github.com/}"
  o="${o%/}"
  printf '%s' "$o"
}

match_glob() {
  local name="$1" pattern="$2"
  # shellcheck disable=SC2053
  [[ "$name" == $pattern ]]
}

parse_repo_jsonl() {
  local json_file="$1" glob="$2" visibility="${3:-all}"
  local -a repos=()
  local slug

  while IFS=$'\t' read -r slug _ _; do
    [[ -n "$slug" ]] || continue
    match_glob "$slug" "$glob" || continue
    repos+=("$slug")
  done < <(jq -rn --arg vis "$visibility" '
    [inputs | select(.record_type == "user_repository")]
    | group_by(.repo_slug)
    | map(sort_by(.generated_at) | last)
    | .[]
    | select($vis == "all" or (.visibility | ascii_downcase) == $vis)
    | [ .repo_slug, (.repo_url // ""), (.default_branch // "") ] | @tsv
  ' "$json_file")

  printf '%s\n' "${repos[@]}"
}

test_normalize_owner_plain() {
  assert_eq "qobeat" "$(normalize_owner "qobeat")"
}

test_normalize_owner_https_url() {
  assert_eq "qobeat" "$(normalize_owner "https://github.com/qobeat")"
}

test_normalize_owner_trailing_slash() {
  assert_eq "qobeat" "$(normalize_owner "https://github.com/qobeat/")"
}

test_match_glob_star() {
  match_glob "my-repo" "*"
}

test_match_glob_prefix() {
  match_glob "ados-foo" "ados-*"
}

test_match_glob_no_match() {
  if match_glob "other" "ados-*"; then
    return 1
  fi
}

test_parse_repo_jsonl_deduplication() {
  local tmp
  tmp="$(mktemp)"
  cat > "$tmp" <<EOF
{"record_type": "user_repository", "repo_slug": "repo-a", "generated_at": "2023-01-01T00:00:00Z"}
{"record_type": "user_repository", "repo_slug": "repo-a", "generated_at": "2023-01-02T00:00:00Z", "default_branch": "main"}
{"record_type": "user_repository", "repo_slug": "repo-b", "repo_url": "git@git", "generated_at": "2023-01-01T00:00:00Z"}
EOF

  mapfile -t slugs < <(parse_repo_jsonl "$tmp" "*")
  rm -f "$tmp"

  assert_eq "2" "${#slugs[@]}"
  assert_eq "repo-a" "${slugs[0]}"
  assert_eq "repo-b" "${slugs[1]}"
}

test_parse_repo_jsonl_glob_filter() {
  local tmp
  tmp="$(mktemp)"
  cat > "$tmp" <<EOF
{"record_type": "user_repository", "repo_slug": "ados-one", "generated_at": "2023-01-01T00:00:00Z"}
{"record_type": "user_repository", "repo_slug": "other-two", "generated_at": "2023-01-01T00:00:00Z"}
{"record_type": "user_repository", "repo_slug": "ados-three", "generated_at": "2023-01-01T00:00:00Z"}
EOF

  mapfile -t slugs < <(parse_repo_jsonl "$tmp" "ados-*")
  rm -f "$tmp"

  assert_eq "2" "${#slugs[@]}"
  assert_eq "ados-one" "${slugs[0]}"
  assert_eq "ados-three" "${slugs[1]}"
}

test_parse_repo_jsonl_visibility_filter() {
  local tmp
  tmp="$(mktemp)"
  cat > "$tmp" <<EOF
{"record_type": "user_repository", "repo_slug": "priv-repo", "visibility": "PRIVATE", "generated_at": "2023-01-01T00:00:00Z"}
{"record_type": "user_repository", "repo_slug": "pub-repo", "visibility": "PUBLIC", "generated_at": "2023-01-01T00:00:00Z"}
EOF

  mapfile -t slugs < <(parse_repo_jsonl "$tmp" "*" "private")
  rm -f "$tmp"

  assert_eq "1" "${#slugs[@]}"
  assert_eq "priv-repo" "${slugs[0]}"
}