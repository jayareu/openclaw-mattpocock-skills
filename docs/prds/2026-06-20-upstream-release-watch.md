# PRD: Upstream Release Watch

## Problem Statement

J.R. wants `mattpocock-skills` to stay current with `mattpocock/skills` release tags without relying on a manual memory or chat-driven sync step. The existing downstream flow can deploy repo changes into Sage main and Sage-soulmate, but the first repo update still has to be created by hand.

## Solution

Add a release-tag watcher to the OpenClaw adaptation repo. It checks the latest upstream GitHub release, syncs the release tag into the adaptation branch, updates the upstream lock, runs validation, and opens or updates a pull request. Merge remains the approval gate; live deployment remains handled by the existing `sage-openclaw` and `sage-soulmate-openclaw` repo automation after those repos bundle the new plugin version.

## User Stories

1. As J.R., I want upstream release watching to run automatically, so that new Matt Pocock skill releases do not depend on a manual reminder.
2. As J.R., I want the watcher to track release tags only, so that unreleased upstream churn does not enter the OpenClaw adaptation.
3. As J.R., I want a pull request instead of a direct main push, so that OpenClaw adaptation changes remain reviewable.
4. As J.R., I want the upstream lock updated with the synced tag and commit, so that the current source of truth is visible from the repo.
5. As J.R., I want validation and security checks to run before the PR is opened, so that broken or suspicious upstream changes are caught early.
6. As J.R., I want a no-op result when the repo is already current, so that scheduled runs stay quiet.
7. As an agent, I want a local testable sync command, so that release sync behavior can be verified without touching GitHub.

## Implementation Decisions

- The sync seam is a repo-local command that can run against either the real upstream or a local test upstream.
- The command defaults to dry-run and requires `--apply` for writes.
- The command does not push branches, open PRs, or install live files.
- GitHub Actions owns the external side effect: scheduled/manual execution, validation, branch push, and pull request creation.
- The release boundary is the upstream GitHub latest release tag, not upstream `main`.
- Existing lock metadata remains the audit record for tag, commit, and sync timestamps.

## Testing Decisions

- Tests exercise the sync command through its public CLI.
- Tests use a temporary local upstream git repository and tags, not network calls.
- The behavior under test is release sync and no-op idempotence, not implementation details.
- Existing adapter validation remains the higher-level check for install policy and target skill sets.

## Out of Scope

- Automatically merging the generated PR.
- Automatically updating `sage-openclaw` and `sage-soulmate-openclaw` from the generated PR.
- Live OpenClaw installation from the watcher.
- Release watching for OpenAI curated plugins such as `openai-developers` and `superpowers`.

## Further Notes

The current durable source flow remains: `openclaw-mattpocock-skills` updates first, then `sage-openclaw` and `sage-soulmate-openclaw` bundle that version, then existing live auto-deploy applies those repo changes.
