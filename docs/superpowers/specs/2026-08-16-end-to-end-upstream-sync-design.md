# End-to-End Matt Pocock Skills Release Sync

**Status:** Approved

## Purpose

Keep the OpenClaw Matt Pocock skills adaptation current with tagged
`mattpocock/skills` releases, propagate each validated adapter release into the
authoritative Sage Main and Soulmate repositories, and deploy those repositories
through the existing GitHub-gated live deployment path.

This replaces the current partially automated chain, where the adapter notices a
new upstream release but a merge conflict can prevent a sync PR and where the two
Sage repositories must still be updated separately.

## Goals

- Track tagged upstream releases only; never consume unreleased `main` changes.
- Preserve OpenClaw-owned adapter behavior while importing every eligible
  upstream addition, modification, rename, and retirement.
- Resolve only explicitly allowlisted, mechanically safe adapter conflicts.
- Fail closed with precise evidence for every unexpected conflict or payload
  change.
- Produce an auditable adapter PR and release, followed by auditable downstream
  PRs in both Sage repositories.
- Use repository-scoped `GITHUB_TOKEN` permissions rather than adding a shared
  cross-repository credential.
- Automatically promote only commits that passed remote and fresh local
  validation, in Soulmate-then-Main order.
- Preserve rollback and recovery evidence at every repository and live-install
  boundary.

## Non-goals

- Mirroring unreleased upstream commits.
- Automatically accepting arbitrary Git conflicts.
- Modifying OpenClaw authentication, provider, or credential state.
- Bypassing the existing `deploy_live.py` and GitHub-gated deployment controls.
- Treating temporary clones or audit worktrees as deployment authority.

## Considered Approaches

### 1. Central push fan-out

The adapter workflow would push updates directly into both Sage repositories.
This is operationally simple but needs a cross-repository personal access token
or GitHub App credential and creates a single high-impact credential boundary.

**Rejected:** unnecessary shared authority and secret-management overhead.

### 2. Direct live-server pull

The Sage host would pull the adapter release and mutate installed skills or the
two persistent repositories directly.

**Rejected:** bypasses repository CI, reviewable history, and the existing
GitHub-gated deployment contract.

### 3. Release-driven downstream pull

The adapter creates a validated release. Each Sage repository uses its own
repository-scoped token to import that release, validate the resulting repository,
record an audit PR, merge the candidate, and explicitly dispatch validation for
the merged commit. Existing Sage timers then deploy the validated repository
commits.

**Selected:** least privilege, clear ownership, no new long-lived secret, and
reuse of the existing fail-closed deployment system.

## Architecture

### Stage A: Upstream release discovery and adapter sync

`openclaw-mattpocock-skills` remains the adaptation source of truth.

1. The scheduled watcher resolves the latest non-draft, non-prerelease tagged
   release from `mattpocock/skills`.
2. The sync command fetches the tag into an isolated ref and verifies the resolved
   commit.
3. A normal Git merge imports upstream history.
4. If the only conflict is `package.json`, a semantic resolver examines the
   base, adapter, and upstream stages. It may preserve only explicitly declared
   adapter-owned fields—initially `scripts.test`—while taking all other fields
   from upstream.
5. The resolver refuses the merge if the adapter changed any non-allowlisted
   `package.json` field, if another file conflicts, or if the JSON structure is
   unexpected.
6. The upstream lock is updated only after a clean merge and records the release
   tag, immutable commit, timestamps, and adapter policy version.
7. Full adapter validation runs before the candidate branch is pushed.
8. The workflow creates or updates `sync-upstream-<tag>` and its PR. Repeated
   schedules are idempotent and refer to the active PR rather than creating
   duplicate failures.

The v1.2.3 conflict is the first regression fixture: upstream's new `version` and
`check-plugin-version` scripts must combine with the adapter's `test` script.

### Stage B: Adapter validation and release

The adapter candidate must pass:

- unit and fixture tests;
- exact manifest and skill-directory validation;
- OpenClaw install-policy validation;
- security scan;
- `git diff --check`;
- a dry-run sync proving the lock is current and the operation is idempotent.

After merge, the release workflow creates a non-draft, non-prerelease adapter
release whose tag and package version match the upstream release and whose tag
resolves to the validated adapter commit. The release is the only downstream
consumption boundary.

### Stage C: Deterministic downstream plugin import

Both `sage-openclaw` and `sage-soulmate-openclaw` receive the same importer and
scheduled workflow.

1. Resolve the latest adapter release and immutable tag commit.
2. Compare it with a downstream lock stored beside the vendored plugin.
3. Materialize only the declared plugin payload into
   `plugins/mattpocock-skills`: `.codex-plugin`, `skills`, `LICENSE`, and
   `README.md`.
4. Replace the managed payload as an exact set, so renamed and retired files do
   not survive as stale extras. Git history remains the repository rollback.
5. Preserve no unlisted downstream overlay inside the managed payload. Any
   required OpenClaw transformation belongs in the adapter source and is tested
   there.
6. Record adapter tag, adapter commit, payload hash, and import timestamp in the
   downstream lock.
7. Run each downstream repository's complete validation suite before pushing a
   candidate branch.
8. Create an audit PR, explicitly dispatch validation for the candidate, and
   merge only the exact validated commit.
9. Explicitly dispatch validation for the merged `main` commit.

GitHub documents that most events caused by `GITHUB_TOKEN` do not recursively
start workflows; `workflow_dispatch` is an explicit exception. The downstream
flow therefore dispatches validation deliberately instead of assuming a bot
push or merge will produce a `push` run.

### Stage D: GitHub-gated live deployment

The existing Sage deployment controllers remain authoritative:

- `sage-dual-profile-github-auto-deploy.timer` runs every five minutes.
- `ordered_dual_profile_auto_deploy.py` deploys Soulmate first, then Main.
- Each profile accepts only an exact `origin/main` commit with successful
  validation for that SHA. Validation may be a trusted `push` run or the explicit
  `workflow_dispatch` run created by the downstream updater.
- Each profile reruns local repository validation and `deploy_live.py --dry-run`
  semantics before applying.
- Managed skill replacements preserve the existing backup/rollback behavior.
- After apply, exact skill inventories, deployment receipts, gateway listeners,
  HTTP readiness, and gateway probes are verified for both profiles.
- A Soulmate authentication guard or any other existing fail-closed condition is
  never weakened; it stops that deployment with evidence.

## Failure Handling

- **No new release:** successful no-op.
- **Known semantic `package.json` overlap:** resolve by the allowlist and test the
  resulting JSON.
- **Unexpected adapter merge conflict:** abort before lock update, report all
  unmerged paths, and leave the staleness alert red.
- **Adapter validation failure:** keep or update the candidate PR and do not
  release.
- **Downstream import mismatch:** keep or update the downstream PR and do not
  merge.
- **Missing candidate validation:** do not merge.
- **Missing merged-commit validation:** Sage controllers skip deployment.
- **One profile fails:** ordered deployment stops; Main is not promoted after a
  Soulmate failure.
- **Live verification fails:** retain repository and deployment receipts for
  rollback; do not claim completion.

## Security Model

- Every workflow receives only the permissions it needs.
- No workflow receives a cross-repository PAT or private key.
- Remote source is pinned by release tag plus resolved commit, not a floating
  branch.
- Unexpected managed-file differences are errors rather than silently preserved
  overlays.
- Third-party Actions references are pinned to immutable commits where practical.
- Logs and artifacts contain no credentials, raw auth database content, or
  provider secrets.

## Testing Strategy

All behavior changes follow red-green-refactor.

### Adapter regression tests

- Reproduce the v1.2.3 three-way `package.json` conflict and require a combined
  result containing upstream version scripts plus adapter `scripts.test`.
- Reject a second conflicting path.
- Reject a non-allowlisted adapter `package.json` change.
- Verify lock updates occur only after a clean merge.
- Verify a repeated sync is a no-op.
- Verify staleness recognizes an active candidate PR.

### Downstream importer tests

- Add, update, rename, and retire skills as an exact managed set.
- Preserve files outside the managed plugin root.
- Reject missing manifests, duplicate skills, path traversal, unexpected
  symlinks, and tag/commit mismatches.
- Verify deterministic payload hashes and no-op idempotence.

### Deployment-controller tests

- Accept successful validation for the exact SHA from `push` or explicit
  `workflow_dispatch`.
- Reject other events, stale SHAs, incomplete runs, and failed conclusions.
- Preserve Soulmate-first ordering and stop-on-first-failure behavior.

## Rollout

1. Merge adapter automation hardening with its regression tests.
2. Run the v1.2.3 sync, validate and merge its PR, and verify adapter release
   `v1.2.3`.
3. Add and validate the downstream importer in both Sage repositories.
4. Trigger both downstream imports and reconcile their payload hashes.
5. Merge Soulmate and Main candidates after exact-SHA validation.
6. Observe the ordered server deployment.
7. Verify repository equality, downstream locks, installed skill inventories,
   deployment receipts, and both gateways.
8. Re-run adapter and downstream staleness workflows to prove steady-state green
   no-ops.

## Completion Criteria

- Adapter lock and release both identify upstream v1.2.3 at
  `6acc160e4e0cd062dbbbd7a1b26ae92855edf07e`.
- The adapter contains the complete validated v1.2.3 skill set with no stale
  retired paths.
- Both downstream repositories contain identical managed plugin payload hashes
  and locks pointing to the same adapter release commit.
- All adapter and downstream checks pass for the merged commits.
- Both persistent Sage checkouts equal `origin/main`.
- Ordered deployment receipts identify those merged commits.
- Main and Soulmate installed skill inventories match their declared policy.
- Both gateway readiness and probe checks pass.
- Re-running every watcher/importer produces a successful no-op.

## References

- GitHub `GITHUB_TOKEN` recursion behavior:
  <https://docs.github.com/en/actions/concepts/security/github_token>
- GitHub workflow dispatch behavior:
  <https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#workflow_dispatch>
