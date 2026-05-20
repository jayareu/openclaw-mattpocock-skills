# OpenClaw Install Policy

This private adaptation keeps the full upstream `mattpocock/skills` repository for auditability, but installs only approved subsets into OpenClaw targets.

## Targets

Codex app-server target:

```text
<profile-home>/agents/main/agent/codex-home/skills
```

OpenClaw-global target:

```text
<profile-home>/skills
```

ACP Codex is explicit only and is not included in `--target all`.

## Default Skill Sets

Codex app-server receives all 14 skills from `.claude-plugin/plugin.json`:

- `diagnose`
- `grill-with-docs`
- `triage`
- `improve-codebase-architecture`
- `setup-matt-pocock-skills`
- `tdd`
- `to-issues`
- `to-prd`
- `zoom-out`
- `prototype`
- `caveman`
- `grill-me`
- `handoff`
- `write-a-skill`

OpenClaw-global receives only:

- `grill-me`
- `handoff`
- `caveman`

`write-a-skill` is intentionally not installed globally. Use native OpenClaw `skill-creator` for global OpenClaw skills and Codex `.system/skill-creator` for Codex app-server skills.

## Explicit-Only Skills

The `misc` skills are kept in this repo but excluded by default:

- `git-guardrails-claude-code`
- `migrate-to-shoehorn`
- `scaffold-exercises`
- `setup-pre-commit`

They may be installed only with `--include-misc` or by explicit `--skills <name>`.

Deprecated, in-progress, and personal skills are never installed by default.

## Safety Rules

- Dry-run is the default.
- Writes require `--apply`.
- Copy is the default live mode.
- Symlink mode is for development only.
- Existing real directories are never replaced unless `--replace` is explicit.
- GitHub repo creation, pushes, live OpenClaw installs, live Codex installs, ACP installs, scheduled automation, and destructive replacements require approval.
