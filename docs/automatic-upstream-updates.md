# Automatic upstream updates

`Sync Upstream Main` runs daily and imports the latest upstream main commit,
including changes that have not received a release tag. Manual dispatch is also
available. The adapter lock records `tracking: main` and the exact upstream SHA;
`releaseTag` remains the last stable tag imported into this checkout, not a claim
that the current main content is a stable release.

Each candidate installs dependencies from its own lock, runs regression tests,
validates the exact promoted skill set and installation policy, performs the
informational security scan, and proves a repeat sync against the same SHA is a
no-op. Unexpected conflicts stop promotion. The candidate is recorded in a
`sync-upstream-main-<SHA>` PR and promoted using an atomic lease on the original main
SHA, with ancestry and exact-head checks. No history rewrite is permitted.
Successful syncs, including no-ops, explicitly dispatch validation on main.

`Release` runs daily and on manual dispatch using the separate `adapter-releases`
branch. That branch starts from the validated v1.3.1 adapter, imports only stable
upstream release tags, runs the full validation suite and package/manifest version
checks, and publishes the corresponding GitHub tag and release. Existing tags
must resolve to the exact validated candidate; mismatches stop publication.
The branch update uses an atomic base lease. Interrupted tag/release publication
is recovered by rerunning the workflow. Unreleased main changes never enter a
stable adapter release. Fixes needed specifically by the release lane must be
applied to that branch explicitly rather than importing upstream main.

The staleness checker verifies both upstream-main SHA equality and latest stable
release publication. Repository-scoped GITHUB_TOKEN is used without a PAT or
shared credentials. Main sync has contents, PR, and Actions write permissions;
release publication only needs contents write. GitHub push protections remain
active, and no admin bypass is used. These workflows do not install live skills
or write downstream repositories. Existing external consumers of stable releases
retain their own configured behavior.

This October 9, 2026 user-approved policy supersedes the older release-only sync
and manual merge rules for the adapter. Other PRs and live deployment boundaries
retain their existing policy.
