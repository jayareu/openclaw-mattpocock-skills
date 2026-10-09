import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtempSync, writeFileSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";

const root = dirname(dirname(fileURLToPath(import.meta.url)));
const sha = "a".repeat(40);
const base = "b".repeat(40);

function run(overrides = {}) {
  const dir = mkdtempSync(join(tmpdir(), "promote-sync-"));
  const log = join(dir, "calls");
  writeFileSync(join(dir, "git"), `#!/usr/bin/env node
const fs = require('fs');
const args = process.argv.slice(2);
fs.appendFileSync(process.env.CALL_LOG, JSON.stringify(args) + String.fromCharCode(10));
if (args[0] === 'rev-parse') console.log(process.env.CHECKOUT_SHA);
if (args[0] === 'push' && process.env.PUSH_FAIL === 'true') process.exit(1);
`, { mode: 0o755 });
  writeFileSync(join(dir, "gh"), `#!/usr/bin/env node
const fs = require('fs');
const args = process.argv.slice(2);
fs.appendFileSync(process.env.CALL_LOG, JSON.stringify(args) + String.fromCharCode(10));
if (args[1]?.endsWith('/commits/main')) console.log(process.env.BASE);
else if (args[1]?.endsWith('/pulls/7')) console.log(process.env.MOCK_PR);
else if (args.includes('PUT')) console.log(process.env.MERGE);
else if (args[0] !== 'workflow') process.exit(1);
`, { mode: 0o755 });
  const pr = { state: "open", draft: false,
    head: { sha, ref: "sync-upstream-v1.3.1", repo: { full_name: "owner/adapter" } },
    base: { ref: "main", repo: { full_name: "owner/adapter" } } };
  let error;
  try {
    execFileSync("bash", [join(root, "scripts/promote-upstream-sync.sh"), "7", sha, base], {
      encoding: "utf8", stdio: ["ignore", "pipe", "pipe"],
      env: { ...process.env, PATH: `${dir}:${process.env.PATH}`,
        GITHUB_REPOSITORY: "owner/adapter", CALL_LOG: log, BASE: base, CHECKOUT_SHA: sha,
        MOCK_PR: JSON.stringify(pr), MERGE: JSON.stringify({ merged: true, sha: "c".repeat(40) }),
        ...overrides }
    });
  } catch (e) { error = e; }
  const calls = readFileSync(log, "utf8").trim().split("\n").map(JSON.parse);
  rmSync(dir, { recursive: true, force: true });
  return { calls, error, pr };
}

test("promotes the exact validated SHA with an atomic base lease", () => {
  const { calls, error } = run();
  assert.equal(error, undefined);
  assert.deepEqual(calls[2], ["rev-parse", "HEAD"]);
  assert.deepEqual(calls[3], ["merge-base", "--is-ancestor", base, sha]);
  assert.deepEqual(calls[4], ["push", `--force-with-lease=refs/heads/main:${base}`, "origin", `${sha}:refs/heads/main`]);
});
test("refuses promotion if main changed during validation", () => {
  const { calls, error } = run({ BASE: "d".repeat(40) });
  assert.ok(error);
  assert.equal(calls.length, 1);
});

test("refuses a changed head, foreign fork, wrong branch, closed or draft PR", () => {
  const { pr } = run();
  for (const mutate of [
    p => p.head.sha = "d".repeat(40),
    p => p.head.repo.full_name = "other/adapter",
    p => p.head.ref = "unrelated",
    p => p.base.ref = "other",
    p => p.state = "closed",
    p => p.draft = true
  ]) {
    const candidate = structuredClone(pr);
    mutate(candidate);
    const { calls, error } = run({ MOCK_PR: JSON.stringify(candidate) });
    assert.ok(error);
    assert.equal(calls.length, 2);
  }
});

test("reports a rejected atomic push and does not continue", () => {
  const { calls, error } = run({ PUSH_FAIL: "true" });
  assert.ok(error);
  assert.equal(calls.length, 5);
});

test("refuses a checkout different from the validated head", () => {
  const { calls, error } = run({ CHECKOUT_SHA: "d".repeat(40) });
  assert.ok(error);
  assert.equal(calls.length, 3);
});
