#!/usr/bin/env node
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { writeFileSync } from "node:fs";

function die(message) {
  console.error(`error: ${message}`);
  process.exit(1);
}

function readStage(stage, path) {
  try {
    return JSON.parse(execFileSync("git", ["show", `:${stage}:${path}`], { encoding: "utf8" }));
  } catch (error) {
    die(`cannot read valid JSON from git stage ${stage} for ${path}: ${error.message}`);
  }
}

function isObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

const path = process.argv[2];
if (path !== "package.json") {
  die("the semantic resolver supports only package.json");
}

const base = readStage(1, path);
const ours = readStage(2, path);
const theirs = readStage(3, path);
if (!isObject(base.scripts) || !isObject(ours.scripts) || !isObject(theirs.scripts)) {
  die("base, adapter, and upstream package.json must contain scripts objects");
}
if (typeof ours.scripts.test !== "string" || ours.scripts.test.length === 0) {
  die("adapter package.json must define a non-empty scripts.test string");
}

const allowedOurs = structuredClone(base);
allowedOurs.scripts.test = ours.scripts.test;
try {
  assert.deepStrictEqual(ours, allowedOurs);
} catch {
  die("adapter package.json changed fields outside the allowlisted scripts.test field");
}

if (Object.hasOwn(theirs.scripts, "test") && theirs.scripts.test !== ours.scripts.test) {
  die("upstream package.json defines a conflicting scripts.test value");
}

const resolved = structuredClone(theirs);
resolved.scripts.test = ours.scripts.test;
writeFileSync(path, JSON.stringify(resolved, null, 2) + "\n");
console.log("Resolved package.json by preserving only adapter-owned scripts.test.");
