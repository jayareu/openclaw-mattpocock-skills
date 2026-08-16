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

Codex app-server receives all 25 skills from `.claude-plugin/plugin.json`:

- `ask-matt`
- `diagnosing-bugs`
- `grill-with-docs`
- `triage`
- `improve-codebase-architecture`
- `setup-matt-pocock-skills`
- `tdd`
- `to-spec`
- `to-tickets`
- `wayfinder`
- `implement`
- `prototype`
- `research`
- `domain-modeling`
- `codebase-design`
- `code-review`
- `resolving-merge-conflicts`
- `wizard`
- `grill-me`
- `grilling`
- `handoff`
- `teach`
- `to-questionnaire`
- `wait-what`
- `writing-for-agents`

OpenClaw-global receives only:

- `grill-me`
- `handoff`

`teach` and the retired `writing-great-skills` name are intentionally not installed globally by default. Use native OpenClaw skills for global OpenClaw skill maintenance and Codex app-server skills for Codex-local skill work.

When a release retires or renames a managed skill, live promotion archives the old managed directory before installing the current manifest. For v1.2.3, `writing-great-skills` is replaced by `writing-for-agents`; `resolving-merge-conflicts`, `wizard`, `to-questionnaire`, and `wait-what` are promoted into the manifest.

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
