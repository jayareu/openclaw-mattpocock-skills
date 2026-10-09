# Automatic upstream updates

The daily `Sync Upstream Release` workflow tracks the latest published stable
`mattpocock/skills` release, retaining release history and adapter behavior.
It also supports manual dispatch. It does not mirror unreleased upstream main.

After sync, it refreshes the manifest count in the adapter lock, validates the
exact promoted skill set and install policy, runs regression tests and the
security review scan, and proves a second sync is a no-op. The workflow installs
ripgrep explicitly so the security scan does not depend on runner image contents.

The validated candidate is pushed to `sync-upstream-<tag>` and recorded in a PR.
The workflow automatically promotes that PR's validated head SHA with a
fast-forward push and an explicit lease on the original main SHA. The lease
atomically rejects concurrent changes to main; an ancestry check forbids history
rewrites. GitHub recognizes the included PR as merged. Foreign, changed, draft,
closed, or unexpected PRs are refused. Repository push protections remain effective.
Unexpected conflicts or validation failures stop before publication or merge.
The security scan reports patterns for review; it is not an automated safety verdict.

Only repository-scoped `GITHUB_TOKEN` is used. The watcher has contents,
pull-request, and Actions write permission; Actions write permits explicitly
dispatching `Validate adapter` after the bot merge. A bot merge does not trigger
push workflows. No PAT, shared credential, branch-protection bypass, live install,
downstream update, or release publication is added by this flow.

Every successful sync, including a no-op, dispatches main validation. If promotion
succeeds but dispatch fails, rerun the watcher to retry, or manually dispatch
`Validate adapter` on main. If main moves or a candidate becomes stale, rerun
the sync watcher; it regenerates and revalidates the candidate from current main.

This user-approved automatic merge replaces the older manual merge gate in the
upstream release watch PRD for adapter release sync PRs only. Other PRs and live
deployment approval boundaries retain their existing policy.
