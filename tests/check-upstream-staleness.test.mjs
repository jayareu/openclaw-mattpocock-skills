import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { chmodSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { rm } from "node:fs/promises";
import { dirname, join } from "node:path";
import { tmpdir } from "node:os";
import { fileURLToPath } from "node:url";
import test from "node:test";

const repoRoot = dirname(dirname(fileURLToPath(import.meta.url)));
const script = join(repoRoot, "scripts", "check-upstream-staleness.sh");

function writeLock(path, tag) {
  writeFileSync(path, JSON.stringify({
    upstream: {
      releaseTag: tag
    }
  }, null, 2) + "\n");
}

function run(args, options = {}) {
  return execFileSync(script, args, {
    encoding: "utf8",
    env: {
      ...process.env,
      ...options.env
    },
    stdio: ["ignore", "pipe", "pipe"]
  });
}

function makeFakeGh(root, exitCode) {
  const path = join(root, "gh");
  writeFileSync(path, `#!/usr/bin/env bash
if [ "$1" = "pr" ] && [ "$2" = "view" ] && [ "${exitCode}" = "0" ]; then
  echo "https://github.com/jayareu/openclaw-mattpocock-skills/pull/9"
  exit 0
fi
exit ${exitCode}
`);
  chmodSync(path, 0o755);
}

test("passes when the upstream lock matches the latest release", async () => {
  const root = mkdtempSync(join(tmpdir(), "mattpocock-stale-test-"));
  try {
    const lock = join(root, "upstream-lock.json");
    writeLock(lock, "v1.1.0");

    const output = run(["--lock-file", lock, "--latest-tag", "v1.1.0"]);

    assert.match(output, /Upstream lock is current: v1\.1\.0/);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test("fails when the upstream lock is stale and no sync PR exists", async () => {
  const root = mkdtempSync(join(tmpdir(), "mattpocock-stale-test-"));
  try {
    const lock = join(root, "upstream-lock.json");
    writeLock(lock, "v1.0.1");
    makeFakeGh(root, 1);

    assert.throws(() => run([
      "--lock-file", lock,
      "--latest-tag", "v1.1.0",
      "--repo", "jayareu/openclaw-mattpocock-skills"
    ], {
      env: { PATH: `${root}:${process.env.PATH}` }
    }), /Upstream lock is stale/);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test("passes when the upstream lock is stale but a sync PR exists", async () => {
  const root = mkdtempSync(join(tmpdir(), "mattpocock-stale-test-"));
  try {
    const lock = join(root, "upstream-lock.json");
    writeLock(lock, "v1.0.1");
    makeFakeGh(root, 0);

    const output = run([
      "--lock-file", lock,
      "--latest-tag", "v1.1.0",
      "--repo", "jayareu/openclaw-mattpocock-skills"
    ], {
      env: { PATH: `${root}:${process.env.PATH}` }
    });

    assert.match(output, /Sync PR already exists/);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});
