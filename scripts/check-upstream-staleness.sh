#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/check-upstream-staleness.sh [--latest-tag TAG] [--repo OWNER/REPO] [--lock-file PATH]

Purpose:
  Fail when mattpocock/skills has a newer release than the local upstream lock
  and no sync PR exists for that release.

Options:
  --latest-tag TAG         Use TAG instead of querying the latest upstream release.
  --repo OWNER/REPO        Repository to inspect for an existing sync PR.
  --lock-file PATH         Override .openclaw/upstream-lock.json.
  --help                   Show this help.
EOF
}

die() {
  echo "error: $*" >&2
  exit 1
}

repo_root() {
  cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd
}

REPO_ROOT="${OPENCLAW_MATTPOCOCK_REPO:-$(git rev-parse --show-toplevel 2>/dev/null || repo_root)}"
LOCK_FILE="$REPO_ROOT/.openclaw/upstream-lock.json"
REPO_SLUG="${GITHUB_REPOSITORY:-jayareu/openclaw-mattpocock-skills}"
LATEST_TAG=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --help|-h)
      usage
      exit 0
      ;;
    --latest-tag)
      [ "$#" -ge 2 ] || die "--latest-tag requires a value"
      LATEST_TAG="$2"
      shift 2
      ;;
    --repo)
      [ "$#" -ge 2 ] || die "--repo requires a value"
      REPO_SLUG="$2"
      shift 2
      ;;
    --lock-file)
      [ "$#" -ge 2 ] || die "--lock-file requires a value"
      LOCK_FILE="$2"
      shift 2
      ;;
    *)
      die "unknown option: $1"
      ;;
  esac
done

[ -f "$LOCK_FILE" ] || die "missing lock file: $LOCK_FILE"

current_tag="$(node -e '
const fs = require("fs");
const lock = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
process.stdout.write(lock.upstream?.releaseTag ?? "");
' "$LOCK_FILE")"

[ -n "$current_tag" ] || die "missing upstream.releaseTag in $LOCK_FILE"

if [ -z "$LATEST_TAG" ]; then
  command -v gh >/dev/null 2>&1 || die "gh is required unless --latest-tag is provided"
  LATEST_TAG="$(gh release view --repo mattpocock/skills --json tagName --jq .tagName)"
fi

[ -n "$LATEST_TAG" ] || die "could not resolve latest upstream release tag"

if [ "$current_tag" = "$LATEST_TAG" ]; then
  echo "Upstream lock is current: $current_tag."
  exit 0
fi

branch="sync-upstream-${LATEST_TAG}"
pr_url="$(gh pr view "$branch" --repo "$REPO_SLUG" --json url --jq .url 2>/dev/null || true)"

if [ -n "$pr_url" ]; then
  echo "Upstream lock is stale: $current_tag < $LATEST_TAG."
  echo "Sync PR already exists: $pr_url"
  exit 0
fi

message="Upstream lock is stale: mattpocock/skills latest release is ${LATEST_TAG}, local lock is ${current_tag}, and no ${branch} PR exists."
echo "error: $message" >&2

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    echo "## Upstream lock stale"
    echo
    echo "- Latest mattpocock/skills release: \`${LATEST_TAG}\`"
    echo "- Local upstream lock: \`${current_tag}\`"
    echo "- Expected sync branch/PR: \`${branch}\`"
    echo
    echo "Run the Sync Upstream Release workflow or inspect why it failed."
  } >>"$GITHUB_STEP_SUMMARY"
fi

exit 1
