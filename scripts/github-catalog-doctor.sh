#!/usr/bin/env bash
# scripts/github-catalog-doctor.sh - Preflight / self-diagnosis (read-only)
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd -- "$SCRIPT_DIR/.." && pwd)}"
# shellcheck source=scripts/github-catalog-lib.sh
source "$SCRIPT_DIR/github-catalog-lib.sh"

usage() {
  cat <<'EOF'
github-catalog-doctor.sh - Preflight checks for github-catalog

Usage:
  scripts/github-catalog-doctor.sh [owner] [--git-host HOST]

Options:
  --git-host HOST   SSH config Host alias to test (default: from catalog.config or github.com)
  -h, --help        Show this help
EOF
}

print_check() {
  local status="$1" label="$2" detail="${3:-}"
  case "$status" in
    ok)    printf '  ✓ %s' "$label" ;;
    warn)  printf '  ⚠ %s' "$label" ;;
    fail)  printf '  ✗ %s' "$label" ;;
  esac
  [[ -n "$detail" ]] && printf ' — %s' "$detail"
  printf '\n'
}

OWNER=""
GIT_HOST_CLI=""
GIT_HOST=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --git-host) GIT_HOST_CLI="${2:?}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    --*) gc_exit_usage "unknown option $1" ;;
    *)
      [[ -z "$OWNER" ]] || gc_exit_usage "unexpected argument: $1"
      OWNER="$1"
      shift
      ;;
  esac
done

if [[ -n "$OWNER" ]]; then
  load_owner_config "$OWNER"
fi

GIT_HOST="$(resolve_option "$GIT_HOST_CLI" "${GITHUB_CATALOG_GIT_HOST:-}" "$(gc_config_get git_host)" "github.com")"

echo "github-catalog doctor"

# bash
if gc_bash_version_ok; then
  print_check ok "bash $(gc_bash_version_string)" "(>= 5.0)"
else
  print_check fail "bash $(gc_bash_version_string)" "(>= 5.0 required)"
fi

# jq
if command -v jq >/dev/null 2>&1 && gc_jq_version_ok; then
  print_check ok "jq $(gc_jq_version_string)" "(>= 1.7)"
else
  ver="$(gc_jq_version_string 2>/dev/null || echo 'not installed')"
  print_check fail "jq $ver" "(>= 1.7 required)"
fi

# git
if command -v git >/dev/null 2>&1; then
  print_check ok "git $(gc_git_version_string)"
else
  print_check fail "git" "not installed"
fi

# gh (optional)
if command -v gh >/dev/null 2>&1; then
  gh_user=""
  gh_host="github.com"
  if gh_status="$(gh auth status -h github.com 2>&1)"; then
    gh_user="$(sed -n 's/.*Logged in to github.com account \([^ ]*\).*/\1/p' <<< "$gh_status" | head -1)"
    [[ -z "$gh_user" ]] && gh_user="$(sed -n 's/.*account \([^ ]*\).*/\1/p' <<< "$gh_status" | head -1)"
    print_check ok "gh $(gh --version 2>/dev/null | head -1 | awk '{print $3}')" "authenticated as: ${gh_user:-unknown} ($gh_host)"
  else
    print_check warn "gh $(gh --version 2>/dev/null | head -1 | awk '{print $3}')" "installed but not authenticated"
  fi
else
  print_check warn "gh" "not installed (required for refresh / wildcard inventory)"
fi

# SSH probe
if [[ -n "$OWNER" ]]; then
  probe_slug="$OWNER"
  inventory="$REPO_ROOT/data/$OWNER/user-repositories.jsonl"
  if [[ -f "$inventory" ]]; then
    probe_slug="$(jq -rn '
      [inputs | select(.record_type == "user_repository")]
      | group_by(.repo_slug) | map(sort_by(.generated_at) | last)
      | map(select((.status // "active") == "active"))
      | .[0].repo_slug // empty
    ' "$inventory" 2>/dev/null || true)"
    [[ -z "$probe_slug" ]] && probe_slug="$OWNER"
  fi

  probe_url="git@${GIT_HOST}:${OWNER}/${probe_slug}.git"
  if git ls-remote "$probe_url" HEAD >/dev/null 2>&1; then
    print_check ok "ssh $GIT_HOST" "\`git ls-remote\` ok for $probe_slug"
  else
    print_check warn "ssh $GIT_HOST" "key loaded or host configured, but \`git ls-remote ${probe_url}\` failed"
  fi
fi

# Inventory
if [[ -n "$OWNER" ]]; then
  data_dir="$REPO_ROOT/data/$OWNER"
  inventory="$data_dir/user-repositories.jsonl"
  catalog="$data_dir/git-projects-catalog.jsonl"

  if [[ -f "$inventory" ]]; then
    read -r inv_count inv_last < <(jq -rn '
      [inputs | select(.record_type == "user_repository")]
      | group_by(.repo_slug) | map(sort_by(.generated_at) | last)
      | [length, (map(.generated_at) | max // "")] | @tsv
    ' "$inventory" 2>/dev/null || printf '0\t')
    inv_last="${inv_last:-unknown}"
    print_check ok "data/$OWNER/" "inventory present ($inv_count repos, last refresh $inv_last)"
  elif [[ -f "$catalog" ]]; then
    print_check warn "data/$OWNER/" "catalog present but no inventory file"
  else
    print_check warn "data/$OWNER/" "no local data yet"
  fi

  if [[ -f "$catalog" ]]; then
    cat_count="$(jq -rn '
      [inputs | select(.record_type == "repo_snapshot")]
      | group_by(.repo_slug) | length
    ' "$catalog" 2>/dev/null || echo 0)"
    run_last="$(jq -rn '
      [inputs | select(.record_type == "run")]
      | sort_by(.generated_at) | last | .report_id // empty
    ' "$catalog" 2>/dev/null || true)"
    detail="$cat_count snapshots"
    [[ -n "$run_last" ]] && detail="$detail, last sync $run_last"
    print_check ok "data/$OWNER/git-projects-catalog.jsonl" "$detail"
  fi

  config_file="$data_dir/catalog.config"
  if [[ -f "$config_file" ]]; then
    print_check ok "data/$OWNER/catalog.config" "present"
  fi
fi
