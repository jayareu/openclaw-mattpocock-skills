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

function hasGitRef(ref, cwd) {
  try {
    git(["rev-parse", "--verify", "--quiet", ref], cwd);
    return true;
  } catch {
    return false;
  }
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
  writeFileSync(join(upstream, "README.md"), "v3\n");
  git(["add", "README.md"], upstream);
  git(["commit", "-q", "-m", "release v1.1.0"], upstream);
  git(["tag", "v1.1.0"], upstream);
  const nextReleaseSha = git(["rev-parse", "v1.1.0^{commit}"], upstream);

  git(["clone", "-q", upstream, downstream], root);
  git(["config", "user.name", "Test"], downstream);
  git(["config", "user.email", "test@example.invalid"], downstream);
  git(["tag", "-d", "v1.0.1"], downstream);
  git(["tag", "-d", "v1.1.0"], downstream);
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

  return { root, upstream, downstream, releaseSha, nextReleaseSha };
}

async function makePackageConflictFixture() {
  const root = mkdtempSync(join(tmpdir(), "mattpocock-package-conflict-test-"));
  const upstream = join(root, "upstream");
  const downstream = join(root, "downstream");
  const basePackage = {
    name: "mattpocock-skills",
    version: "1.1.0",
    scripts: {
      changeset: "changeset",
      version: "changeset version"
    }
  };

  await mkdir(upstream, { recursive: true });
  git(["init", "-q"], upstream);
  git(["config", "user.name", "Test"], upstream);
  git(["config", "user.email", "test@example.invalid"], upstream);
  writeFileSync(join(upstream, "package.json"), JSON.stringify(basePackage, null, 2) + "\n");
  writeFileSync(join(upstream, "CONTEXT.md"), "base\n");
  git(["add", "package.json", "CONTEXT.md"], upstream);
  git(["commit", "-q", "-m", "release v1.1.0"], upstream);
  git(["tag", "v1.1.0"], upstream);
  const baseSha = git(["rev-parse", "v1.1.0^{commit}"], upstream);

  git(["clone", "-q", upstream, downstream], root);
  git(["config", "user.name", "Test"], downstream);
  git(["config", "user.email", "test@example.invalid"], downstream);
  git(["tag", "-d", "v1.1.0"], downstream);
  git(["switch", "-q", "-c", "main"], downstream);
  await mkdir(join(downstream, ".openclaw"), { recursive: true });
  writeFileSync(
    join(downstream, ".openclaw", "upstream-lock.json"),
    JSON.stringify({
      upstream: {
        cloneUrl: upstream,
        releaseTag: "v1.1.0",
        sha: baseSha
      }
    }, null, 2) + "\n"
  );
  basePackage.scripts.test = "node --test tests/*.test.mjs";
  writeFileSync(join(downstream, "package.json"), JSON.stringify(basePackage, null, 2) + "\n");
  git(["add", ".openclaw/upstream-lock.json", "package.json"], downstream);
  git(["commit", "-q", "-m", "add OpenClaw test script"], downstream);

  const upstreamPackage = {
    name: "mattpocock-skills",
    version: "1.2.3",
    scripts: {
      changeset: "changeset",
      version: "changeset version && node scripts/sync-plugin-version.mjs",
      "check-plugin-version": "node scripts/sync-plugin-version.mjs --check"
    }
  };
  writeFileSync(join(upstream, "package.json"), JSON.stringify(upstreamPackage, null, 2) + "\n");
  git(["add", "package.json"], upstream);
  git(["commit", "-q", "-m", "release v1.2.3"], upstream);
  git(["tag", "v1.2.3"], upstream);
  const releaseSha = git(["rev-parse", "v1.2.3^{commit}"], upstream);

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

test("does not clobber unrelated local tags while fetching a requested release tag", async () => {
  const fixture = await makeFixture();
  try {
    git(["tag", "-f", "v1.0.1", "HEAD"], fixture.downstream);
    const localTagSha = git(["rev-parse", "v1.0.1^{commit}"], fixture.downstream);

    run([
      "--tag", "v1.1.0",
      "--upstream-repo", fixture.upstream,
      "--apply"
    ], fixture.downstream);

    const lock = JSON.parse(readFileSync(join(fixture.downstream, ".openclaw", "upstream-lock.json"), "utf8"));
    assert.equal(lock.upstream.releaseTag, "v1.1.0");
    assert.equal(lock.upstream.sha, fixture.nextReleaseSha);
    assert.equal(git(["rev-parse", "v1.0.1^{commit}"], fixture.downstream), localTagSha);
    assert.equal(hasGitRef("refs/tags/v1.1.0", fixture.downstream), false);
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

test("resolves the allowlisted package conflict", async () => {
  const fixture = await makePackageConflictFixture();
  try {
    run([
      "--tag", "v1.2.3",
      "--upstream-repo", fixture.upstream,
      "--apply"
    ], fixture.downstream);

    const packageJson = JSON.parse(readFileSync(join(fixture.downstream, "package.json"), "utf8"));
    assert.equal(packageJson.version, "1.2.3");
    assert.deepEqual(packageJson.scripts, {
      changeset: "changeset",
      test: "node --test tests/*.test.mjs",
      version: "changeset version && node scripts/sync-plugin-version.mjs",
      "check-plugin-version": "node scripts/sync-plugin-version.mjs --check"
    });
    assert.equal(git(["diff", "--name-only", "--diff-filter=U"], fixture.downstream), "");
    const lock = JSON.parse(readFileSync(join(fixture.downstream, ".openclaw", "upstream-lock.json"), "utf8"));
    assert.equal(lock.upstream.releaseTag, "v1.2.3");
    assert.equal(lock.upstream.sha, fixture.releaseSha);
  } finally {
    await rm(fixture.root, { recursive: true, force: true });
  }
});

test("rejects a package conflict with non-allowlisted adapter changes", async () => {
  const fixture = await makePackageConflictFixture();
  try {
    const packagePath = join(fixture.downstream, "package.json");
    const packageJson = JSON.parse(readFileSync(packagePath, "utf8"));
    packageJson.description = "adapter-only change";
    writeFileSync(packagePath, JSON.stringify(packageJson, null, 2) + "\n");
    git(["add", "package.json"], fixture.downstream);
    git(["commit", "--amend", "-q", "--no-edit"], fixture.downstream);

    assert.throws(() => run([
      "--tag", "v1.2.3",
      "--upstream-repo", fixture.upstream,
      "--apply"
    ], fixture.downstream), /outside the allowlisted scripts\.test field/);

    const lock = JSON.parse(readFileSync(join(fixture.downstream, ".openclaw", "upstream-lock.json"), "utf8"));
    assert.equal(lock.upstream.releaseTag, "v1.1.0");
  } finally {
    await rm(fixture.root, { recursive: true, force: true });
  }
});

test("rejects package auto-resolution when another path conflicts", async () => {
  const fixture = await makePackageConflictFixture();
  try {
    writeFileSync(join(fixture.downstream, "CONTEXT.md"), "adapter\n");
    git(["add", "CONTEXT.md"], fixture.downstream);
    git(["commit", "--amend", "-q", "--no-edit"], fixture.downstream);

    writeFileSync(join(fixture.upstream, "CONTEXT.md"), "upstream\n");
    git(["add", "CONTEXT.md"], fixture.upstream);
    git(["commit", "-q", "-m", "update context"], fixture.upstream);
    git(["tag", "-f", "v1.2.3"], fixture.upstream);

    assert.throws(() => run([
      "--tag", "v1.2.3",
      "--upstream-repo", fixture.upstream,
      "--apply"
    ], fixture.downstream), /unsupported conflicts:.*CONTEXT\.md.*package\.json|unsupported conflicts:.*package\.json.*CONTEXT\.md/);

    const lock = JSON.parse(readFileSync(join(fixture.downstream, ".openclaw", "upstream-lock.json"), "utf8"));
    assert.equal(lock.upstream.releaseTag, "v1.1.0");
  } finally {
    await rm(fixture.root, { recursive: true, force: true });
  }
});
