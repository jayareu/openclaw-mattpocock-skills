import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";

const repoRoot = dirname(dirname(fileURLToPath(import.meta.url)));
const workflowDir = join(repoRoot, ".github", "workflows");
const workflowNames = [
  "check-upstream-staleness.yml",
  "release.yml",
  "sync-upstream-release.yml"
];

function workflow(name) {
  return readFileSync(join(workflowDir, name), "utf8");
}

test("validates an upstream candidate before pushing or opening a PR", () => {
  const text = workflow("sync-upstream-release.yml");
  const validateIndex = text.indexOf("name: Validate adapter");
  const pushIndex = text.indexOf("name: Push sync branch");
  const prIndex = text.indexOf("name: Open or update pull request");

  assert.notEqual(validateIndex, -1);
  assert.notEqual(pushIndex, -1);
  assert.notEqual(prIndex, -1);
  assert.ok(validateIndex < pushIndex, "validation must precede branch push");
  assert.ok(validateIndex < prIndex, "validation must precede PR mutation");
});

test("pins every referenced GitHub Action to an immutable commit", () => {
  for (const name of workflowNames) {
    const usesLines = workflow(name).split("\n").filter((line) => line.trim().startsWith("uses:"));
    assert.ok(usesLines.length > 0, `${name} must use at least one Action`);
    for (const line of usesLines) {
      assert.match(line, /uses:\s+[\w.-]+\/[\w.-]+@[0-9a-f]{40}(?:\s+#\s+v[^\s]+)?\s*$/i, `${name}: ${line.trim()}`);
    }
  }
});
