#!/usr/bin/env bash
set -euo pipefail

# Called only after the workflow validates this exact candidate checkout.
# No credentials, downstream writes, releases, or live installation are added.
PR="${1:?pull request number required}"
HEAD_SHA="${2:?validated head SHA required}"
BASE_SHA="${3:?original main SHA required}"
REPO="${GITHUB_REPOSITORY:?repository required}"
[[ "$PR" =~ ^[0-9]+$ ]] || exit 1
[[ "$HEAD_SHA" =~ ^[0-9a-f]{40}$ && "$BASE_SHA" =~ ^[0-9a-f]{40}$ ]] || exit 1

current_base="$(gh api "repos/$REPO/commits/main" --jq .sha)"
if [ "$current_base" != "$BASE_SHA" ]; then
  echo "error: main changed during validation; retry sync against current main" >&2
  exit 1
fi

metadata="$(gh api "repos/$REPO/pulls/$PR")"
printf '%s' "$metadata" | node -e '
let input = "";
process.stdin.on("data", chunk => input += chunk);
process.stdin.on("end", () => {
  const pr = JSON.parse(input);
  const [repo, sha] = process.argv.slice(1);
  if (pr.state !== "open" || pr.draft || pr.head.sha !== sha ||
      pr.head.repo.full_name !== repo || pr.base.repo.full_name !== repo ||
      pr.base.ref !== "main" || !/^sync-upstream-(v|main-[0-9a-f]{40}$)/.test(pr.head.ref)) {
    throw new Error("refusing to merge an unexpected or changed sync candidate");
  }
});
' "$REPO" "$HEAD_SHA"

# The candidate must descend from the original main and match this checkout.
[ "$(git rev-parse HEAD)" = "$HEAD_SHA" ] || exit 1
git merge-base --is-ancestor "$BASE_SHA" "$HEAD_SHA"
# The lease is a server-side compare-and-swap. An advanced main is rejected.
# Ancestry above guarantees this is a fast-forward, never a history rewrite.
# Repository push protections remain effective; no admin bypass is used.
git push --force-with-lease="refs/heads/main:$BASE_SHA" origin "$HEAD_SHA:refs/heads/main"
echo "Promoted validated upstream candidate: $HEAD_SHA"
