# Issues: Upstream Release Watch

## 1. Add a Testable Upstream Release Sync Command

## What to build

Create a local command that syncs the adaptation repo to a requested upstream release tag or the latest upstream release tag. It should update the upstream lock only when the target release differs from the current lock.

## Acceptance criteria

- [x] A local command can sync a specific release tag.
- [x] The command updates upstream lock metadata with the tag, commit, and timestamps.
- [x] The command reports no change when already synced.
- [x] The command defaults to dry-run and requires `--apply` for writes.
- [x] Tests verify sync and no-op behavior through the command interface.

## Blocked by

None - can start immediately.

## 2. Add Scheduled GitHub Release Watching

## What to build

Add a GitHub Action that checks upstream releases on a schedule and through manual dispatch. When a new release is found, it should run the sync command, validate the repo, push a sync branch, and open or update a pull request.

## Acceptance criteria

- [x] Workflow runs on a schedule.
- [x] Workflow can be triggered manually.
- [x] Workflow opens or updates a PR instead of pushing directly to `main`.
- [x] Workflow runs tests, adapter validation, security scan, and diff checks before PR creation.
- [x] Workflow no-ops when already current.

## Blocked by

Issue 1.

## 3. Document the Release-Watch Product Contract

## What to build

Record the product contract and operational boundaries for upstream release watching so future agents understand the intended flow.

## Acceptance criteria

- [x] PRD captures release-tag-only strategy.
- [x] PRD captures PR-based approval gate.
- [x] PRD states that live install and downstream repo bundling remain separate.
- [x] Vertical slices are documented as completed issues.

## Blocked by

None - can start immediately.
