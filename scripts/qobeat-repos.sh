: ${REPO_OWNER:="qobeat"}
: ${REPO_LIST_FILE:=repos.txt}
: ${REPO_MASK:="*"}
: ${REPO_TYPE:="private"}
: ${PARALLEL:="4"}

if (($# == 0 )); then
  echo "Usage: $0 [--repo-list-file <file>] --repo-mask <mask> [--repo-type <type>] [--parallel <parallel>]"
  exit 1
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo-list-file) REPO_LIST_FILE="${2:?}"; shift 2 ;;
    --repo-mask) REPO_MASK="${2:?}"; shift 2 ;;
    --repo-type) REPO_TYPE="${2:?}"; shift 2 ;;
    --parallel) PARALLEL="${2:?}"; shift 2 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

./scripts/github-catalog-orchestrator.sh \
  --owner "$REPO_OWNER" \
  --repos "$REPO_MASK" \
  --type "$REPO_TYPE"
  --repo-list-file "$REPO_LIST_FILE" \
  --parallel "$PARALLEL"