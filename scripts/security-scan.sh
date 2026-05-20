#!/usr/bin/env bash
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$REPO"

if ! command -v rg >/dev/null 2>&1; then
  echo "error: rg is required for security-scan.sh" >&2
  exit 1
fi

echo "Security scan: review hits manually. Expected hits may include issue tracker workflows and documented dangerous-command guardrails."

patterns=(
  'OPENAI_API_KEY|GITHUB_TOKEN|GITLAB_TOKEN|ANTHROPIC_API_KEY'
  'password|passwd|secret|token|cookie'
  '~/.ssh|id_rsa|id_ed25519'
  '~/.openclaw|SOUL.md|USER.md|MEMORY.md|IDENTITY.md'
  '\bsudo\b'
  'rm[[:space:]]+-rf'
  'base64[[:space:]]+(-d|--decode)'
  '\beval\b|exec\('
  '\bcurl\b|\bwget\b'
  'gh[[:space:]]+issue|glab[[:space:]]+issue'
)

status=0
for pattern in "${patterns[@]}"; do
  echo
  echo "== pattern: $pattern =="
  if rg -n --hidden --glob '!.git/**' --glob '!node_modules/**' --glob '!scripts/security-scan.sh' "$pattern" .; then
    status=1
  else
    echo "no hits"
  fi
done

if [ "$status" -eq 1 ]; then
  echo
  echo "Security scan completed with review hits."
else
  echo
  echo "Security scan completed with no hits."
fi
