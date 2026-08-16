# GitHub-Gated Live Deployment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Allow the existing Sage deploy controllers to accept explicit exact-SHA validation dispatches and prove both profiles reach the same validated plugin release.

**Architecture:** Extend only the validation-evidence query; keep every existing clean-tree, fast-forward, local-check, lock, deployment, and ordering guard. The already installed five-minute ordered timer remains the sole automatic live mutation path.

**Tech Stack:** Python 3, pytest, GitHub Actions API, systemd user units, OpenClaw CLI.

## Global Constraints

- Accept only completed successful `push` or `workflow_dispatch` validation for the exact `origin/main` SHA.
- Do not accept pull-request, schedule, or unrelated workflow runs.
- Preserve Soulmate-first ordering and stop on the first failure.
- Do not modify credentials or weaken the Soulmate auth-store guard.
- Completion requires repository, installed-payload, deployment-receipt, listener, HTTP readiness, and gateway-probe evidence.

---

### Task 1: Exact-SHA dispatch validation evidence

**Files in both Sage repositories:**
- Modify: `scripts/github_auto_deploy.py`
- Modify: `tests/test_github_auto_deploy.py`

**Interfaces:**
- Consumes: GitHub workflow-run objects with `head_sha`, `event`, `status`, and `conclusion`.
- Produces: `github_actions_success(sha) -> bool` accepting only trusted events for the exact SHA.

- [ ] **Step 1: Write the failing dispatch acceptance test**

```python
runs = [{
    "head_sha": "abc123",
    "event": "workflow_dispatch",
    "status": "completed",
    "conclusion": "success",
}]
assert ctl.github_actions_success("abc123") is True
```

Add a table rejecting `pull_request`, `schedule`, stale SHA, incomplete, cancelled, and failed runs.

- [ ] **Step 2: Run the focused tests for RED**

Run: `python -m pytest -q tests/test_github_auto_deploy.py -k github_actions_success`

Expected: workflow-dispatch case fails because the API query is push-only.

- [ ] **Step 3: Implement the minimal evidence filter**

Query completed branch runs without an event filter and accept an item only when:

```python
item.get("head_sha") == sha
and item.get("event") in {"push", "workflow_dispatch"}
and item.get("status") == "completed"
and item.get("conclusion") == "success"
```

- [ ] **Step 4: Run focused and full tests for GREEN**

Run in each repository:

`python -m pytest -q tests/test_github_auto_deploy.py && python scripts/validate_repo.py && python scripts/sanitize_check.py && python -m pytest -q`

- [ ] **Step 5: Commit in each repository**

```bash
git add scripts/github_auto_deploy.py tests/test_github_auto_deploy.py
git commit -m "fix: accept dispatched exact-SHA validation"
```

### Task 2: Publish and validate controller changes

- [ ] Push each downstream branch and include the controller change in its PR.
- [ ] Wait for PR validation and merge Soulmate first, then Main.
- [ ] Dispatch `validate.yml` on both merged main commits and record exact-SHA success.

### Task 3: Ordered live rollout

- [ ] **Step 1: Capture pre-deploy evidence**

Read-only verify both persistent checkouts, `origin/main` SHAs, tracked cleanliness, active timer state, current deployment receipts, installed plugin hashes, and gateway readiness.

- [ ] **Step 2: Run ordered dry-run**

Run remotely:

`cd /home/sage/repos/sage-openclaw && python3 scripts/ordered_dual_profile_auto_deploy.py --dry-run`

Expected: Soulmate then Main validation succeeds with no unsupported writes.

- [ ] **Step 3: Run ordered apply**

Run remotely:

`cd /home/sage/repos/sage-openclaw && python3 scripts/ordered_dual_profile_auto_deploy.py --apply`

Expected: exact validated commits deploy in Soulmate-then-Main order.

- [ ] **Step 4: Verify deployment receipts and repository equality**

Require each persistent checkout to be clean on `main`, equal `origin/main`, and have a deployment receipt whose `deployedSha` is that commit.

- [ ] **Step 5: Verify exact installed plugin state**

Reconcile adapter release commit, both downstream locks, both vendored payload hashes, both live marketplace payload hashes, and the policy-selected installed skill directories.

- [ ] **Step 6: Verify both gateways**

Check systemd user service state, listeners on ports 18809 then 18789, `/readyz`, and profile-scoped gateway probes.

- [ ] **Step 7: Prove stable no-op**

Run ordered dry-run again and dispatch adapter/downstream watchers. Require successful no-op results and no new repository or live changes.

