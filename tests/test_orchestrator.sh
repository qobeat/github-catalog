#!/usr/bin/env bash
# Unit tests for orchestrator helpers (no network)

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

parse_repo_list() {
  local list_file="$1" glob="$2"
  local -a repos=()
  local line slug _url _branch count=0

  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -z "$line" ]] && continue

    slug="" _url="" _branch=""
    read -r slug _url _branch <<< "$line"
    [[ -n "$slug" ]] || continue
    match_glob "$slug" "$glob" || continue

    repos+=("$slug")
    count=$((count + 1))
  done < "$list_file"

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

test_parse_repo_list_comments_and_urls() {
  local tmp
  tmp="$(mktemp)"
  cat > "$tmp" <<'EOF'
# comment line
repo-a
repo-b  git@github.com:owner/repo-b.git  develop
repo-c  file:///tmp/x.git
EOF

  mapfile -t slugs < <(parse_repo_list "$tmp" "*")
  rm -f "$tmp"

  assert_eq "3" "${#slugs[@]}"
  assert_eq "repo-a" "${slugs[0]}"
  assert_eq "repo-b" "${slugs[1]}"
  assert_eq "repo-c" "${slugs[2]}"
}

test_parse_repo_list_glob_filter() {
  local tmp
  tmp="$(mktemp)"
  printf '%s\n' 'ados-one' 'other-two' 'ados-three' > "$tmp"

  mapfile -t slugs < <(parse_repo_list "$tmp" "ados-*")
  rm -f "$tmp"

  assert_eq "2" "${#slugs[@]}"
  assert_eq "ados-one" "${slugs[0]}"
  assert_eq "ados-three" "${slugs[1]}"
}
