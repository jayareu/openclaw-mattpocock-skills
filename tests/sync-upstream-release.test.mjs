import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { mkdir, rm } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";
import { tmpdir } from "node:os";

const repoRoot = dirname(dirname(fileURLToPath(import.meta.url)));
const script = join(repoRoot, "scripts", "sync-upstream-release.sh");

function git(args, cwd) {
  return execFileSync("git", args, { cwd, encoding: "utf8" }).trim();
}

function run(args, cwd) {
  return execFileSync(script, args, { cwd, encoding: "utf8" });
}

async function makeFixture() {
  const root = mkdtempSync(join(tmpdir(), "mattpocock-sync-test-"));
  const upstream = join(root, "upstream");
  const downstream = join(root, "downstream");

  await mkdir(upstream, { recursive: true });
  git(["init", "-q"], upstream);
  git(["config", "user.name", "Test"], upstream);
  git(["config", "user.email", "test@example.invalid"], upstream);
  writeFileSync(join(upstream, "README.md"), "v1\n");
  git(["add", "README.md"], upstream);
  git(["commit", "-q", "-m", "initial"], upstream);
  git(["tag", "v1.0.0"], upstream);
  writeFileSync(join(upstream, "README.md"), "v2\n");
  git(["add", "README.md"], upstream);
  git(["commit", "-q", "-m", "release v1.0.1"], upstream);
  git(["tag", "v1.0.1"], upstream);
  const releaseSha = git(["rev-parse", "v1.0.1^{commit}"], upstream);

  git(["clone", "-q", upstream, downstream], root);
  git(["config", "user.name", "Test"], downstream);
  git(["config", "user.email", "test@example.invalid"], downstream);
  git(["checkout", "-q", "v1.0.0"], downstream);
  git(["switch", "-q", "-c", "main"], downstream);
  await mkdir(join(downstream, ".openclaw"), { recursive: true });
  writeFileSync(
    join(downstream, ".openclaw", "upstream-lock.json"),
    JSON.stringify({
      upstream: {
        repo: "https://github.com/mattpocock/skills",
        cloneUrl: upstream,
        branch: "main",
        releaseTag: "v1.0.0",
        sha: git(["rev-parse", "v1.0.0^{commit}"], upstream),
        auditedAt: "2026-01-01T00:00:00Z",
        verifiedAt: "2026-01-01T00:00:00Z",
        syncedAt: "2026-01-01T00:00:00Z"
      },
      installPolicy: {
        codexAppServer: { defaultCount: 1, source: ".claude-plugin/plugin.json" }
      },
      localPatches: []
    }, null, 2) + "\n"
  );
  git(["add", ".openclaw/upstream-lock.json"], downstream);
  git(["commit", "-q", "-m", "add lock"], downstream);

  return { root, upstream, downstream, releaseSha };
}

test("syncs a requested release tag and updates the upstream lock", async () => {
  const fixture = await makeFixture();
  try {
    const envFile = join(fixture.root, "result.env");
    run([
      "--tag", "v1.0.1",
      "--upstream-repo", fixture.upstream,
      "--apply",
      "--env-file", envFile
    ], fixture.downstream);

    const lock = JSON.parse(readFileSync(join(fixture.downstream, ".openclaw", "upstream-lock.json"), "utf8"));
    assert.equal(lock.upstream.releaseTag, "v1.0.1");
    assert.equal(lock.upstream.sha, fixture.releaseSha);
    assert.equal(readFileSync(join(fixture.downstream, "README.md"), "utf8"), "v2\n");
    assert.match(readFileSync(envFile, "utf8"), /UPSTREAM_SYNC_CHANGED=true/);
  } finally {
    await rm(fixture.root, { recursive: true, force: true });
  }
});

test("reports no change when the lock already matches the requested release tag", async () => {
  const fixture = await makeFixture();
  try {
    run([
      "--tag", "v1.0.1",
      "--upstream-repo", fixture.upstream,
      "--apply"
    ], fixture.downstream);
    const head = git(["rev-parse", "HEAD"], fixture.downstream);
    const envFile = join(fixture.root, "noop.env");

    run([
      "--tag", "v1.0.1",
      "--upstream-repo", fixture.upstream,
      "--apply",
      "--env-file", envFile
    ], fixture.downstream);

    assert.equal(git(["rev-parse", "HEAD"], fixture.downstream), head);
    assert.match(readFileSync(envFile, "utf8"), /UPSTREAM_SYNC_CHANGED=false/);
  } finally {
    await rm(fixture.root, { recursive: true, force: true });
  }
});
