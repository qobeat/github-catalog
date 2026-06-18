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

glob_has_wildcards() {
  [[ "$1" == *[\*\?\[]* ]]
}

build_git_repo_url() {
  local owner="$1" slug="$2"
  local host="${GIT_HOST:-github.com}"
  printf 'git@%s:%s/%s.git' "$host" "$owner" "$slug"
}

setup_git_ssh() {
  [[ -z "$SSH_KEY" ]] && return 0
  export GIT_SSH_COMMAND="ssh -i ${SSH_KEY} -o IdentitiesOnly=yes -o BatchMode=yes"
}

needs_gh_inventory() {
  (( REFRESH_REPO_LIST == 1 )) && return 0
  glob_has_wildcards "$REPOS_GLOB" && return 0
  [[ -z "$GIT_HOST" ]] && return 0
  return 1
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

test_glob_has_wildcards() {
  glob_has_wildcards "ados-*"
  glob_has_wildcards "repo?"
  if glob_has_wildcards "ados-framework"; then
    return 1
  fi
}

test_build_git_repo_url_default() {
  GIT_HOST=""
  assert_eq "git@github.com:qobeat/ados-proj.git" \
    "$(build_git_repo_url "qobeat" "ados-proj")"
}

test_build_git_repo_url_custom_host() {
  GIT_HOST="github-personal"
  assert_eq "git@github-personal:qobeat/ados-proj.git" \
    "$(build_git_repo_url "qobeat" "ados-proj")"
  GIT_HOST=""
}

test_setup_git_ssh() {
  unset GIT_SSH_COMMAND
  SSH_KEY=""
  setup_git_ssh
  [[ -z "${GIT_SSH_COMMAND:-}" ]]

  SSH_KEY="/tmp/fake-key"
  setup_git_ssh
  assert_eq "ssh -i /tmp/fake-key -o IdentitiesOnly=yes -o BatchMode=yes" "$GIT_SSH_COMMAND"
  unset GIT_SSH_COMMAND SSH_KEY
}

test_needs_gh_inventory_skips_for_literal_git_host() {
  REPOS_GLOB="ados-proj"
  REFRESH_REPO_LIST=0
  GIT_HOST="github-personal"
  if needs_gh_inventory; then
    REPOS_GLOB="" REFRESH_REPO_LIST=0 GIT_HOST=""
    return 1
  fi
  REPOS_GLOB="" REFRESH_REPO_LIST=0 GIT_HOST=""
}

test_needs_gh_inventory_requires_wildcard() {
  REPOS_GLOB="ados-*"
  REFRESH_REPO_LIST=0
  GIT_HOST="github-personal"
  needs_gh_inventory || { REPOS_GLOB="" GIT_HOST=""; return 1; }
  REPOS_GLOB="" GIT_HOST=""
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