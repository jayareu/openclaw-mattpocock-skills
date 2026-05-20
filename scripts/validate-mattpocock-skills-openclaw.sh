#!/usr/bin/env bash
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALLER="$REPO/scripts/install-mattpocock-skills-openclaw.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

pass() {
  echo "PASS: $*"
}

assert_dirs_exact() {
  local dir="$1"
  shift
  local expected
  local actual
  expected="$(printf '%s\n' "$@" | sort)"
  actual="$(find "$dir" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort)"
  if [ "$actual" != "$expected" ]; then
    echo "Expected dirs:" >&2
    printf '%s\n' "$expected" >&2
    echo "Actual dirs:" >&2
    printf '%s\n' "$actual" >&2
    fail "directory set mismatch for $dir"
  fi
}

assert_fails() {
  local label="$1"
  shift
  if "$@" >/tmp/openclaw-mattpocock-negative.out 2>&1; then
    cat /tmp/openclaw-mattpocock-negative.out >&2
    fail "expected failure: $label"
  fi
  pass "$label failed as expected"
}

cd "$REPO"

bash -n scripts/*.sh
pass "shell syntax"

node <<'NODE'
const fs = require("fs");
const path = require("path");
const plugin = JSON.parse(fs.readFileSync(".claude-plugin/plugin.json", "utf8"));
if (!Array.isArray(plugin.skills)) throw new Error("plugin.skills is not an array");
if (plugin.skills.length !== 14) throw new Error(`expected 14 manifest skills, got ${plugin.skills.length}`);
const names = plugin.skills.map((rel) => path.basename(rel));
const unique = new Set(names);
if (unique.size !== names.length) throw new Error("duplicate manifest skill names");
for (const rel of plugin.skills) {
  const skillMd = path.join(rel.replace(/^\.\//, ""), "SKILL.md");
  if (!fs.existsSync(skillMd)) throw new Error(`missing ${skillMd}`);
}
const globalDefault = ["grill-me", "handoff", "caveman"];
if (globalDefault.includes("write-a-skill")) throw new Error("write-a-skill must not be global default");
const misc = fs.readdirSync("skills/misc").filter((name) => fs.existsSync(path.join("skills/misc", name, "SKILL.md")));
if (misc.length !== 4) throw new Error(`expected 4 misc skills, got ${misc.length}`);
console.log("PASS: manifest policy");
NODE

if command -v npx >/dev/null 2>&1; then
  npx --yes skills@latest add . --list >/tmp/openclaw-mattpocock-skills-list.txt
  if [ "$(sed '/^[[:space:]]*$/d' /tmp/openclaw-mattpocock-skills-list.txt | wc -l)" -lt 14 ]; then
    cat /tmp/openclaw-mattpocock-skills-list.txt >&2
    fail "skills CLI list returned fewer than 14 lines"
  fi
  pass "skills CLI list"
else
  echo "WARN: npx not found; skipping skills CLI list"
fi

CODEX_SKILLS=(
  diagnose
  grill-with-docs
  triage
  improve-codebase-architecture
  setup-matt-pocock-skills
  tdd
  to-issues
  to-prd
  zoom-out
  prototype
  caveman
  grill-me
  handoff
  write-a-skill
)

OPENCLAW_SKILLS=(
  grill-me
  handoff
  caveman
)

MISC_SKILLS=(
  git-guardrails-claude-code
  migrate-to-shoehorn
  scaffold-exercises
  setup-pre-commit
)

tmp_codex="$(mktemp -d)"
"$INSTALLER" --profile-path "$tmp_codex" --target codex >/tmp/openclaw-mattpocock-dry-codex.txt
"$INSTALLER" --profile-path "$tmp_codex" --target codex --apply >/tmp/openclaw-mattpocock-apply-codex.txt
assert_dirs_exact "$tmp_codex/agents/main/agent/codex-home/skills" "${CODEX_SKILLS[@]}"
pass "temp codex apply exact set"

tmp_openclaw="$(mktemp -d)"
"$INSTALLER" --profile-path "$tmp_openclaw" --target openclaw >/tmp/openclaw-mattpocock-dry-openclaw.txt
"$INSTALLER" --profile-path "$tmp_openclaw" --target openclaw --apply >/tmp/openclaw-mattpocock-apply-openclaw.txt
assert_dirs_exact "$tmp_openclaw/skills" "${OPENCLAW_SKILLS[@]}"
pass "temp openclaw apply exact set"

tmp_all="$(mktemp -d)"
"$INSTALLER" --profile-path "$tmp_all" --target all --apply >/tmp/openclaw-mattpocock-apply-all.txt
assert_dirs_exact "$tmp_all/agents/main/agent/codex-home/skills" "${CODEX_SKILLS[@]}"
assert_dirs_exact "$tmp_all/skills" "${OPENCLAW_SKILLS[@]}"
[ ! -e "$tmp_all/acpx/codex-home/skills" ] || fail "--target all created ACP skills without --include-acp"
pass "target all excludes ACP"

tmp_misc="$(mktemp -d)"
"$INSTALLER" --profile-path "$tmp_misc" --target codex --include-misc --apply >/tmp/openclaw-mattpocock-apply-misc.txt
assert_dirs_exact "$tmp_misc/agents/main/agent/codex-home/skills" "${CODEX_SKILLS[@]}" "${MISC_SKILLS[@]}"
pass "include misc expands codex set"

tmp_explicit="$(mktemp -d)"
"$INSTALLER" --profile-path "$tmp_explicit" --target openclaw --skills write-a-skill --apply >/tmp/openclaw-mattpocock-explicit-write-a-skill.txt
assert_dirs_exact "$tmp_explicit/skills" write-a-skill
pass "explicit write-a-skill allowed only when named"

assert_fails "existing target without --replace" "$INSTALLER" --profile-path "$tmp_openclaw" --target openclaw --apply
assert_fails "unknown skill" "$INSTALLER" --profile-path "$(mktemp -d)" --target codex --skills not-a-skill --apply
assert_fails "deprecated skill excluded" "$INSTALLER" --profile-path "$(mktemp -d)" --target codex --skills qa --apply

tmp_replace="$(mktemp -d)"
"$INSTALLER" --profile-path "$tmp_replace" --target openclaw --apply >/tmp/openclaw-mattpocock-replace-first.txt
"$INSTALLER" --profile-path "$tmp_replace" --target openclaw --replace --apply >/tmp/openclaw-mattpocock-replace-second.txt
assert_dirs_exact "$tmp_replace/skills" "${OPENCLAW_SKILLS[@]}"
pass "replace works when explicit"

tmp_acp="$(mktemp -d)"
"$INSTALLER" --profile-path "$tmp_acp" --target acp-codex --apply >/tmp/openclaw-mattpocock-acp.txt
assert_dirs_exact "$tmp_acp/acpx/codex-home/skills" "${CODEX_SKILLS[@]}"
pass "explicit acp-codex works"

echo "All OpenClaw Matt Pocock skills validation checks passed."
