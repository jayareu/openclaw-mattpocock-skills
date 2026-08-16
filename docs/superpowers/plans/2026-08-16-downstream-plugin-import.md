# Downstream Plugin Import Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make both Sage repositories pull the latest validated adapter release into an exact, auditable vendored plugin payload.

**Architecture:** Each downstream repository owns its updater and uses only its repository-scoped token. A deterministic Python importer consumes an extracted adapter release, replaces the managed plugin root exactly, records tag/commit/hash metadata, and refuses malformed sources.

**Tech Stack:** Python 3, pytest, GitHub Actions, GitHub CLI, Git.

## Global Constraints

- Apply identical importer behavior to `sage-openclaw` and `sage-soulmate-openclaw`.
- Manage only `plugins/mattpocock-skills` and its adjacent lock.
- Never preserve undocumented overlays inside the managed plugin root.
- Never add a PAT, private key, or cross-repository credential.
- Validate the candidate before push and validate the exact merge commit before live deployment.

---

### Task 1: Exact-set importer in Sage Main

**Files:**
- Create: `scripts/sync_mattpocock_plugin.py`
- Create: `tests/test_sync_mattpocock_plugin.py`
- Create: `plugins/mattpocock-skills.lock.json`
- Modify: `scripts/validate_repo.py`

**Interfaces:**
- Consumes: `sync_mattpocock_plugin.py --source DIR --tag TAG --commit SHA [--apply]`.
- Produces: exact plugin payload and lock keys `adapterTag`, `adapterCommit`, `payloadSha256`, `fileCount`, and `syncedAt`.

- [ ] **Step 1: Write failing importer tests**

Create real temporary source and destination trees. Assert addition, update, retirement, path traversal rejection, symlink rejection, malformed manifest rejection, dry-run no-write behavior, deterministic hash, and repeated-apply no-op.

```python
result = sync_plugin(source, destination, tag="v1.2.3", commit="a" * 40, apply=True)
assert result.changed is True
assert not (destination / "skills" / "retired" / "SKILL.md").exists()
assert json.loads(lock.read_text())["adapterCommit"] == "a" * 40
```

- [ ] **Step 2: Run the importer test for RED**

Run: `python -m pytest -q tests/test_sync_mattpocock_plugin.py`

Expected: import failure because the module does not exist.

- [ ] **Step 3: Implement the minimal importer**

Use a staging directory under the destination parent, copy only `.codex-plugin`, `skills`, `LICENSE`, and `README.md`, reject symlinks and escaping paths, calculate the normalized content hash, then replace the destination only under `--apply`.

- [ ] **Step 4: Run the importer test for GREEN**

Run: `python -m pytest -q tests/test_sync_mattpocock_plugin.py`

Expected: all importer tests pass.

- [ ] **Step 5: Make repository validation lock-driven**

Replace hard-coded v1.2.3 payload constants with the lock's literal file count, hash, tag, and commit while retaining exact manifest and frontmatter policy checks.

- [ ] **Step 6: Run the full Main suite**

Run: `python scripts/validate_repo.py && python scripts/sanitize_check.py && python -m pytest -q`

Expected: all checks pass.

- [ ] **Step 7: Commit Main importer**

```bash
git add scripts/sync_mattpocock_plugin.py tests/test_sync_mattpocock_plugin.py scripts/validate_repo.py plugins/mattpocock-skills.lock.json
git commit -m "feat: import validated Matt Pocock releases"
```

### Task 2: Port and independently verify Soulmate

**Files:**
- Create the same importer, test, and lock paths in `sage-soulmate-openclaw`.
- Modify: `scripts/validate_repo.py`

**Interfaces:** Same CLI and lock schema as Task 1.

- [ ] **Step 1: Add the same failing behavior tests to Soulmate**

Run: `python -m pytest -q tests/test_sync_mattpocock_plugin.py`

Expected: RED before the Soulmate importer exists.

- [ ] **Step 2: Port the reviewed importer and lock validation**

Keep byte-identical shared importer code; retain Soulmate-only auth checks outside this module.

- [ ] **Step 3: Verify Soulmate GREEN**

Run: `python scripts/validate_repo.py && python scripts/sanitize_check.py && python -m pytest -q`

Expected: all checks pass, including the auth guard tests.

- [ ] **Step 4: Reconcile shared-file hashes**

Compare importer and importer-test SHA256 values between repositories; require equality.

- [ ] **Step 5: Commit Soulmate importer**

```bash
git add scripts/sync_mattpocock_plugin.py tests/test_sync_mattpocock_plugin.py scripts/validate_repo.py plugins/mattpocock-skills.lock.json
git commit -m "feat: import validated Matt Pocock releases"
```

### Task 3: Repository-scoped update workflows

**Files in both downstream repositories:**
- Create: `.github/workflows/sync-mattpocock-plugin.yml`
- Modify: `.github/workflows/validate.yml`
- Modify: `tests/test_github_workflow.py`

**Interfaces:**
- Consumes: latest non-draft adapter release tag and resolved tag commit.
- Produces: deterministic `sync-mattpocock-<tag>` PR, candidate validation dispatch, merge, and merged-SHA validation dispatch.

- [ ] **Step 1: Write failing workflow behavior tests**

Require schedule and manual dispatch, `contents: write`, `pull-requests: write`, `actions: write`, exact adapter tag/commit verification, full local validation, deterministic branch naming, PR idempotence, and explicit candidate/main `workflow_dispatch` calls.

- [ ] **Step 2: Run workflow tests for RED**

Run: `python -m pytest -q tests/test_github_workflow.py`

Expected: FAIL because the sync workflow and dispatch trigger are absent.

- [ ] **Step 3: Implement the workflows**

Add `workflow_dispatch` to `validate.yml`. In the sync workflow, download the adapter tag into a temporary directory, verify its commit, run the importer, run all validation, push the candidate, create/update the PR, dispatch candidate validation, wait for exact-SHA success, merge the exact head SHA, then dispatch validation on `main`.

- [ ] **Step 4: Verify workflow tests GREEN**

Run: `python -m pytest -q tests/test_github_workflow.py`

Expected: PASS in both repositories.

- [ ] **Step 5: Run complete local gates in both repositories**

Run in each: `python scripts/validate_repo.py && python scripts/sanitize_check.py && python -m pytest -q && git diff --check`

- [ ] **Step 6: Commit each workflow change**

```bash
git add .github/workflows tests/test_github_workflow.py
git commit -m "ci: automate Matt Pocock plugin updates"
```

### Task 4: Publish downstream changes

- [ ] Push both branches and create separate PRs.
- [ ] Wait for exact-SHA GitHub validation in both repositories.
- [ ] Merge Soulmate first, then Main.
- [ ] Dispatch `validate.yml` for each merged `main` and record successful run URLs.
- [ ] Dispatch each plugin sync workflow again and require successful no-op output.
