# Adapter Release Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make tagged upstream releases merge, validate, and release reliably while resolving only the known OpenClaw-owned `package.json` field.

**Architecture:** Keep the upstream Git merge so history remains auditable. Add a fail-closed semantic resolver that operates on Git's three index stages and preserves only `scripts.test`; every other conflict remains fatal.

**Tech Stack:** Bash, Node.js 22, Node test runner, Git, GitHub Actions, Changesets.

## Global Constraints

- Track non-draft, non-prerelease upstream release tags only.
- Preserve only the allowlisted adapter field `package.json:scripts.test` during semantic conflict resolution.
- Update `.openclaw/upstream-lock.json` only after the merge is clean.
- Never hide unexpected conflicts or weaken security validation.
- The target release is upstream v1.2.3 at `6acc160e4e0cd062dbbbd7a1b26ae92855edf07e`.

---

### Task 1: Semantic package conflict resolution

**Files:**
- Create: `scripts/resolve-package-json-conflict.mjs`
- Modify: `scripts/sync-upstream-release.sh`
- Modify: `tests/sync-upstream-release.test.mjs`

**Interfaces:**
- Consumes: Git index stages `:1:package.json`, `:2:package.json`, and `:3:package.json`.
- Produces: `node scripts/resolve-package-json-conflict.mjs package.json`; exit 0 with a staged-safe working-tree file or nonzero with a precise refusal.

- [ ] **Step 1: Write the failing v1.2.3-shaped test**

Create a fixture where the adapter adds `scripts.test` while upstream changes `version`, changes `scripts.version`, and adds `scripts.check-plugin-version`. Invoke the real sync CLI and assert the literal combined JSON plus a clean index.

```js
assert.deepEqual(result.scripts, {
  changeset: "changeset",
  test: "node --test tests/*.test.mjs",
  version: "changeset version && node scripts/sync-plugin-version.mjs",
  "check-plugin-version": "node scripts/sync-plugin-version.mjs --check"
});
assert.equal(git(["diff", "--name-only", "--diff-filter=U"], downstream), "");
```

- [ ] **Step 2: Run the focused test and verify RED**

Run: `node --test --test-name-pattern="resolves the allowlisted package conflict" tests/sync-upstream-release.test.mjs`

Expected: FAIL because `git merge` exits on the package conflict.

- [ ] **Step 3: Implement the minimal resolver**

Read all three index stages with `git show`. Require that the adapter-versus-base delta is exactly the addition or change of `scripts.test`. Start from upstream JSON, insert the adapter test script, write two-space JSON with a trailing newline, and leave staging to the shell caller.

```js
const resolved = structuredClone(theirs);
resolved.scripts.test = ours.scripts.test;
fs.writeFileSync(path, JSON.stringify(resolved, null, 2) + "\n");
```

Wrap `git merge --no-edit "$FETCH_REF"` in a conditional. Invoke the resolver only when `git diff --name-only --diff-filter=U` is exactly `package.json`, then `git add package.json` and `git commit --no-edit`.

- [ ] **Step 4: Run the focused test and verify GREEN**

Run: `node --test --test-name-pattern="resolves the allowlisted package conflict" tests/sync-upstream-release.test.mjs`

Expected: PASS.

- [ ] **Step 5: Add fail-closed tests**

Add separate fixtures for an additional conflicting file and for an adapter change to `package.json:version`. Assert nonzero exit, unchanged lock tag, and no success metadata.

- [ ] **Step 6: Run the sync test file**

Run: `node --test tests/sync-upstream-release.test.mjs`

Expected: all sync tests pass.

- [ ] **Step 7: Commit**

```bash
git add scripts/resolve-package-json-conflict.mjs scripts/sync-upstream-release.sh tests/sync-upstream-release.test.mjs
git commit -m "fix: resolve allowlisted upstream package conflicts"
```

### Task 2: Candidate and steady-state workflow hardening

**Files:**
- Modify: `.github/workflows/sync-upstream-release.yml`
- Modify: `.github/workflows/check-upstream-staleness.yml`
- Modify: `tests/check-upstream-staleness.test.mjs`
- Create: `tests/workflow-contracts.test.mjs`

**Interfaces:**
- Consumes: sync CLI outputs `UPSTREAM_SYNC_TAG`, `UPSTREAM_SYNC_SHA`, and `UPSTREAM_SYNC_CHANGED`.
- Produces: one candidate PR per release and a green no-op after the release lock is current.

- [ ] **Step 1: Write failing workflow behavior tests**

Parse the YAML as text and require full validation before branch push, explicit least-privilege permissions, immutable action SHAs, and PR idempotence. Extend staleness tests to distinguish current, active-candidate, and missing-candidate states.

- [ ] **Step 2: Run workflow and staleness tests for RED**

Run: `node --test tests/check-upstream-staleness.test.mjs tests/workflow-contracts.test.mjs`

Expected: FAIL on the missing workflow contracts.

- [ ] **Step 3: Harden both workflows**

Run `npm test`, adapter validation, security scan, and `git diff --check` before push. Keep the PR branch deterministic and update an existing PR rather than force-creating duplicates. Pin first-party and Changesets actions to immutable commits with version comments.

- [ ] **Step 4: Verify GREEN**

Run: `npm test`

Expected: all Node tests pass.

- [ ] **Step 5: Commit**

```bash
git add .github/workflows tests
git commit -m "ci: harden upstream release candidates"
```

### Task 3: Sync and release v1.2.3

**Files:**
- Modify through sync: upstream-tracked files and `.openclaw/upstream-lock.json`

**Interfaces:**
- Consumes: upstream tag v1.2.3 and the hardened sync command.
- Produces: a validated merge commit, current lock, adapter PR, merged main, and adapter release v1.2.3.

- [ ] **Step 1: Run the real sync locally**

Run: `scripts/sync-upstream-release.sh --tag v1.2.3 --apply`

Expected: clean semantic resolution; lock identifies v1.2.3 and `6acc160e...`.

- [ ] **Step 2: Run complete local verification**

Run: `npm ci && npm test && scripts/validate-mattpocock-skills-openclaw.sh && scripts/security-scan.sh && git diff --check`

Expected: exit 0 for every command.

- [ ] **Step 3: Push the branch and create a PR**

Push the current branch, open a PR against `main`, and wait for all GitHub checks.

- [ ] **Step 4: Merge and verify release**

Merge normally, wait for the Release workflow, and verify that v1.2.3 is non-draft, non-prerelease, and resolves to merged `main`.

- [ ] **Step 5: Prove steady-state no-op**

Dispatch both release watcher workflows and require successful no-op conclusions.

