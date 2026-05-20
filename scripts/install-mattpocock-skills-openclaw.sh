#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/install-mattpocock-skills-openclaw.sh [options]

Defaults:
  --profile main --target codex --dry-run

Profiles:
  --profile main|sage-soulmate
  --profile-path DIR
  --all-profiles

Targets:
  --target codex|openclaw|acp-codex|all
  --include-acp              Include ACP only with --target all.

Selection:
  --skills a,b,c             Install only named skills.
  --include-misc             Include misc skills in target defaults.

Writes:
  --apply                    Perform writes. Omit for dry-run.
  --dry-run                  Force dry-run.
  --replace                  Replace existing skill target dirs.
  --symlink                  Symlink instead of copy. Development only.

Examples:
  scripts/install-mattpocock-skills-openclaw.sh
  scripts/install-mattpocock-skills-openclaw.sh --profile main --target codex --apply
  scripts/install-mattpocock-skills-openclaw.sh --profile main --target openclaw --apply
EOF
}

die() {
  echo "error: $*" >&2
  exit 1
}

repo_root() {
  cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd
}

REPO="$(repo_root)"
PROFILE="main"
PROFILE_PATH=""
ALL_PROFILES=0
TARGET="codex"
APPLY=0
REPLACE=0
SYMLINK=0
INCLUDE_MISC=0
INCLUDE_ACP=0
SKILLS_ARG=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --help|-h)
      usage
      exit 0
      ;;
    --profile)
      [ "$#" -ge 2 ] || die "--profile requires a value"
      PROFILE="$2"
      shift 2
      ;;
    --profile-path)
      [ "$#" -ge 2 ] || die "--profile-path requires a value"
      PROFILE_PATH="$2"
      shift 2
      ;;
    --all-profiles)
      ALL_PROFILES=1
      shift
      ;;
    --target)
      [ "$#" -ge 2 ] || die "--target requires a value"
      TARGET="$2"
      shift 2
      ;;
    --skills)
      [ "$#" -ge 2 ] || die "--skills requires a value"
      SKILLS_ARG="$2"
      shift 2
      ;;
    --include-misc)
      INCLUDE_MISC=1
      shift
      ;;
    --include-acp)
      INCLUDE_ACP=1
      shift
      ;;
    --apply)
      APPLY=1
      shift
      ;;
    --dry-run)
      APPLY=0
      shift
      ;;
    --replace)
      REPLACE=1
      shift
      ;;
    --symlink)
      SYMLINK=1
      shift
      ;;
    *)
      die "unknown option: $1"
      ;;
  esac
done

case "$TARGET" in
  codex|openclaw|acp-codex|all) ;;
  *) die "invalid --target: $TARGET" ;;
esac

case "$PROFILE" in
  main|sage-soulmate) ;;
  *) die "invalid --profile: $PROFILE" ;;
esac

if [ "$ALL_PROFILES" -eq 1 ] && [ -n "$PROFILE_PATH" ]; then
  die "--all-profiles cannot be combined with --profile-path"
fi

if [ "$SYMLINK" -eq 1 ] && [ "$APPLY" -eq 1 ]; then
  echo "warning: --symlink is intended for development installs only" >&2
fi

SKILL_MAP="$(mktemp)"
cleanup() {
  rm -f "$SKILL_MAP"
}
trap cleanup EXIT

node - "$REPO" >"$SKILL_MAP" <<'NODE'
const fs = require("fs");
const path = require("path");

const repo = process.argv[2];
const pluginPath = path.join(repo, ".claude-plugin", "plugin.json");
const plugin = JSON.parse(fs.readFileSync(pluginPath, "utf8"));
const seen = new Set();

for (const rel of plugin.skills) {
  const cleanRel = rel.replace(/^\.\//, "");
  const name = path.basename(cleanRel);
  const skillMd = path.join(repo, cleanRel, "SKILL.md");
  if (!fs.existsSync(skillMd)) {
    throw new Error(`manifest skill missing SKILL.md: ${rel}`);
  }
  seen.add(name);
  console.log(["manifest", name, cleanRel].join("\t"));
}

const miscDir = path.join(repo, "skills", "misc");
if (fs.existsSync(miscDir)) {
  for (const name of fs.readdirSync(miscDir).sort()) {
    const cleanRel = path.join("skills", "misc", name);
    const skillMd = path.join(repo, cleanRel, "SKILL.md");
    if (fs.existsSync(skillMd) && !seen.has(name)) {
      console.log(["misc", name, cleanRel].join("\t"));
    }
  }
}
NODE

skill_path() {
  awk -F '\t' -v name="$1" '$2 == name { print $3; found = 1; exit } END { if (!found) exit 1 }' "$SKILL_MAP"
}

manifest_names() {
  awk -F '\t' '$1 == "manifest" { print $2 }' "$SKILL_MAP"
}

misc_names() {
  awk -F '\t' '$1 == "misc" { print $2 }' "$SKILL_MAP"
}

default_names_for_target() {
  case "$1" in
    codex|acp-codex)
      manifest_names
      if [ "$INCLUDE_MISC" -eq 1 ]; then
        misc_names
      fi
      ;;
    openclaw)
      printf '%s\n' grill-me handoff caveman
      if [ "$INCLUDE_MISC" -eq 1 ]; then
        misc_names
      fi
      ;;
    *)
      die "internal error: unknown target for defaults: $1"
      ;;
  esac
}

selected_names_for_target() {
  if [ -n "$SKILLS_ARG" ]; then
    printf '%s\n' "$SKILLS_ARG" | tr ',' '\n' | sed '/^[[:space:]]*$/d'
  else
    default_names_for_target "$1"
  fi
}

profile_home() {
  case "$1" in
    main) printf '%s\n' "$HOME/.openclaw" ;;
    sage-soulmate) printf '%s\n' "$HOME/.openclaw-sage-soulmate" ;;
    *) die "internal error: unknown profile: $1" ;;
  esac
}

target_dir() {
  local profile_home="$1"
  local target="$2"
  case "$target" in
    codex) printf '%s\n' "$profile_home/agents/main/agent/codex-home/skills" ;;
    openclaw) printf '%s\n' "$profile_home/skills" ;;
    acp-codex) printf '%s\n' "$profile_home/acpx/codex-home/skills" ;;
    *) die "internal error: unknown target: $target" ;;
  esac
}

targets_to_run() {
  case "$TARGET" in
    all)
      printf '%s\n' codex openclaw
      if [ "$INCLUDE_ACP" -eq 1 ]; then
        printf '%s\n' acp-codex
      fi
      ;;
    *)
      printf '%s\n' "$TARGET"
      ;;
  esac
}

profiles_to_run() {
  if [ -n "$PROFILE_PATH" ]; then
    printf '%s\t%s\n' custom "$PROFILE_PATH"
  elif [ "$ALL_PROFILES" -eq 1 ]; then
    printf '%s\t%s\n' main "$(profile_home main)"
    printf '%s\t%s\n' sage-soulmate "$(profile_home sage-soulmate)"
  else
    printf '%s\t%s\n' "$PROFILE" "$(profile_home "$PROFILE")"
  fi
}

install_one() {
  local src="$1"
  local dest="$2"

  if [ -e "$dest" ] || [ -L "$dest" ]; then
    if [ "$REPLACE" -ne 1 ]; then
      die "target exists; pass --replace to replace: $dest"
    fi
    if [ "$APPLY" -eq 1 ]; then
      if [ -L "$dest" ] || [ -f "$dest" ]; then
        rm -f -- "$dest"
      elif [ -d "$dest" ]; then
        rm -r -- "$dest"
      else
        die "refusing to replace unsupported filesystem object: $dest"
      fi
    fi
  fi

  if [ "$APPLY" -eq 0 ]; then
    if [ "$SYMLINK" -eq 1 ]; then
      echo "[dry-run] symlink $dest -> $src"
    else
      echo "[dry-run] copy $src -> $dest"
    fi
    return
  fi

  mkdir -p "$(dirname "$dest")"
  if [ "$SYMLINK" -eq 1 ]; then
    ln -s "$src" "$dest"
    echo "symlinked $dest -> $src"
  else
    cp -a "$src" "$dest"
    echo "copied $src -> $dest"
  fi
}

while IFS=$'\t' read -r profile_label profile_dir; do
  [ -n "$profile_dir" ] || die "empty profile dir for $profile_label"
  while IFS= read -r this_target; do
    dest_root="$(target_dir "$profile_dir" "$this_target")"
    echo "profile=$profile_label target=$this_target dest=$dest_root mode=$([ "$APPLY" -eq 1 ] && echo apply || echo dry-run)"
    selected_names_for_target "$this_target" | while IFS= read -r skill_name; do
      [ -n "$skill_name" ] || continue
      rel="$(skill_path "$skill_name")" || die "unknown or excluded skill: $skill_name"
      src="$REPO/$rel"
      [ -f "$src/SKILL.md" ] || die "missing SKILL.md for $skill_name at $src"
      install_one "$src" "$dest_root/$skill_name"
    done
  done < <(targets_to_run)
done < <(profiles_to_run)
