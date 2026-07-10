#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/sync-upstream-release.sh --latest [--apply] [--env-file PATH]
  scripts/sync-upstream-release.sh --tag TAG [--apply] [--upstream-repo URL_OR_PATH] [--env-file PATH]

Purpose:
  Sync this OpenClaw adaptation to an upstream mattpocock/skills release tag.

Defaults:
  Dry-run only. No branch creation, push, PR, or live install.

Options:
  --latest                 Resolve the latest GitHub release tag from mattpocock/skills.
  --tag TAG                Sync a specific release tag.
  --upstream-repo VALUE    Override upstream remote URL/path.
  --apply                  Merge the tag and update .openclaw/upstream-lock.json.
  --env-file PATH          Write GitHub-output-compatible sync metadata.
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

REPO="${OPENCLAW_MATTPOCOCK_REPO:-$(git rev-parse --show-toplevel 2>/dev/null || repo_root)}"
LOCK_FILE="$REPO/.openclaw/upstream-lock.json"
UPSTREAM_REPO=""
TAG=""
LATEST=0
APPLY=0
ENV_FILE=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --help|-h)
      usage
      exit 0
      ;;
    --latest)
      LATEST=1
      shift
      ;;
    --tag)
      [ "$#" -ge 2 ] || die "--tag requires a value"
      TAG="$2"
      shift 2
      ;;
    --upstream-repo)
      [ "$#" -ge 2 ] || die "--upstream-repo requires a value"
      UPSTREAM_REPO="$2"
      shift 2
      ;;
    --apply)
      APPLY=1
      shift
      ;;
    --env-file)
      [ "$#" -ge 2 ] || die "--env-file requires a value"
      ENV_FILE="$2"
      shift 2
      ;;
    *)
      die "unknown option: $1"
      ;;
  esac
done

[ -f "$LOCK_FILE" ] || die "missing lock file: $LOCK_FILE"

if [ "$LATEST" -eq 1 ] && [ -n "$TAG" ]; then
  die "--latest and --tag are mutually exclusive"
fi

if [ "$LATEST" -eq 0 ] && [ -z "$TAG" ]; then
  die "pass --latest or --tag TAG"
fi

json_get() {
  node -e '
const fs = require("fs");
const path = process.argv[1];
const keyPath = process.argv[2].split(".");
let value = JSON.parse(fs.readFileSync(path, "utf8"));
for (const key of keyPath) value = value?.[key];
if (typeof value === "string") process.stdout.write(value);
' "$LOCK_FILE" "$1"
}

current_tag="$(json_get upstream.releaseTag || true)"
current_sha="$(json_get upstream.sha || true)"
if [ -z "$UPSTREAM_REPO" ]; then
  UPSTREAM_REPO="$(json_get upstream.cloneUrl || true)"
fi
[ -n "$UPSTREAM_REPO" ] || UPSTREAM_REPO="https://github.com/mattpocock/skills.git"

if [ "$LATEST" -eq 1 ]; then
  if ! command -v gh >/dev/null 2>&1; then
    die "gh is required for --latest"
  fi
  TAG="$(gh release view --repo mattpocock/skills --json tagName --jq .tagName)"
fi

[ -n "$TAG" ] || die "could not resolve release tag"
case "$TAG" in
  v*) ;;
  *) die "release tag must start with v: $TAG" ;;
esac

cd "$REPO"

if [ "$APPLY" -eq 1 ] && [ -n "$(git status --porcelain)" ]; then
  die "working tree is dirty; commit or stash changes before syncing"
fi

FETCH_REF="refs/upstream-sync/$TAG"
git fetch --no-tags "$UPSTREAM_REPO" "+refs/tags/$TAG:$FETCH_REF" >/dev/null
target_sha="$(git rev-parse "$FETCH_REF^{commit}")"

write_env() {
  if [ -n "$ENV_FILE" ]; then
    {
      printf 'UPSTREAM_SYNC_TAG=%s\n' "$TAG"
      printf 'UPSTREAM_SYNC_SHA=%s\n' "$target_sha"
      printf 'UPSTREAM_SYNC_PREVIOUS_TAG=%s\n' "$current_tag"
      printf 'UPSTREAM_SYNC_PREVIOUS_SHA=%s\n' "$current_sha"
      printf 'UPSTREAM_SYNC_CHANGED=%s\n' "$1"
    } >"$ENV_FILE"
  fi
}

if [ "$current_tag" = "$TAG" ] && [ "$current_sha" = "$target_sha" ]; then
  echo "Already synced to $TAG ($target_sha)."
  write_env false
  exit 0
fi

echo "Current upstream lock: ${current_tag:-unknown} ${current_sha:-unknown}"
echo "Target upstream release: $TAG $target_sha"

if [ "$APPLY" -eq 0 ]; then
  echo "Dry-run only. Re-run with --apply to merge and update lock."
  write_env true
  exit 0
fi

git merge --no-edit "$FETCH_REF"

timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
node - "$LOCK_FILE" "$TAG" "$target_sha" "$timestamp" <<'NODE'
const fs = require("fs");
const [path, tag, sha, timestamp] = process.argv.slice(2);
const lock = JSON.parse(fs.readFileSync(path, "utf8"));
lock.upstream = lock.upstream || {};
lock.upstream.releaseTag = tag;
lock.upstream.sha = sha;
lock.upstream.auditedAt = timestamp;
lock.upstream.verifiedAt = timestamp;
lock.upstream.syncedAt = timestamp;
fs.writeFileSync(path, JSON.stringify(lock, null, 2) + "\n");
NODE

git add "$LOCK_FILE"
git commit -m "Update upstream lock for $TAG" >/dev/null

echo "Synced upstream release $TAG."
write_env true
