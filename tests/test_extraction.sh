#!/usr/bin/env bash
# Unit tests for README semantic extraction (matches datafetcher extract_section)

extract_section() {
  local keyword="$1"
  local file_content="$2"
  LC_ALL=C awk -v kw="$keyword" '
    BEGIN { kw_lower = tolower(kw) }
    p && /^#{1,4} / { exit }
    /^#{1,4} / {
      heading = $0
      sub(/^#+[[:space:]]+/, "", heading)
      hl = tolower(heading)
      if (hl == kw_lower || index(hl, kw_lower) > 0) { p = 1; next }
    }
    p { print }
  ' <<< "$file_content"
}

strip_blank_lines() {
  LC_ALL=C sed '/^[[:space:]]*$/d'
}

SAMPLE_README='# Fake Project

## GOAL
Test the sentry and collection logic.

## OBJECTIVES
1. Write a JSONL line
2. Skip on re-run

## Typical Workflows
install.sh runs here.

## REQUIREMENTS
Must support --owner.
'

test_extract_goal() {
  local got
  got=$(extract_section "GOAL" "$SAMPLE_README" | strip_blank_lines)
  assert_eq "Test the sentry and collection logic." "$got"
}

test_extract_objectives() {
  local got
  mapfile -t lines < <(extract_section "OBJECTIVES" "$SAMPLE_README" | strip_blank_lines)
  assert_eq "2" "${#lines[@]}"
  assert_eq "1. Write a JSONL line" "${lines[0]}"
  assert_eq "2. Skip on re-run" "${lines[1]}"
}

test_extract_workflows() {
  local got
  got=$(extract_section "Typical Workflows" "$SAMPLE_README" | strip_blank_lines)
  assert_eq "install.sh runs here." "$got"
}

test_extract_workflows_fallback() {
  local readme='# Title

## Workflows
Fallback path works.
'
  local got
  got=$(extract_section "Typical Workflows" "$readme" | strip_blank_lines)
  if [[ -z "${got//[$'\t\r\n ']/}" ]]; then
    got=$(extract_section "Workflows" "$readme" | strip_blank_lines)
  fi
  assert_eq "Fallback path works." "$got"
}

test_extract_empty_readme() {
  local got
  got=$(extract_section "GOAL" "" | strip_blank_lines)
  assert_eq "" "$got"
}

test_assert_eq_works() {
  assert_eq "hello" "hello"
}
