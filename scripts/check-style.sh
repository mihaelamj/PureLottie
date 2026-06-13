#!/usr/bin/env bash
# CI style gate (github-discipline section 7, "ship both" with the commit-msg hook).
#
# Two scans, scoped to the rule and the repo's current state:
#   1. AI-attribution / watermark patterns: scanned across the whole tracked tree
#      (currently clean), so no attribution trailer or watermark can land anywhere.
#      This script is excluded from that scan because it necessarily names the
#      forbidden patterns it looks for.
#   2. Em dashes: scanned only in files changed versus the base ref (a forward
#      gate). The repo carries a pre-existing em-dash backlog tracked separately;
#      gating only changed files stops new ones without blocking on that cleanup.
#      With no base ref argument, staged files are scanned instead.
#
# Usage: scripts/check-style.sh [base-ref]
# Exit 0 = clean; exit 1 = a violation, printed with file:line.
set -euo pipefail

# Em dash byte sequence (U+2014), built from bytes so this source carries none.
emdash=$(printf '\xe2\x80\x94')
fail=0

# 1. Attribution / watermark, whole tracked tree (skip binary with -I, exclude self).
attribution='Co-authored-by:|Generated (with|by) (Claude|Codex|Cursor|Copilot|Gemini|ChatGPT)|<!-- *(claude|codex|cursor|copilot|gemini|generated) *-->'
# Capture output rather than trust xargs' aggregated exit code (xargs returns 123
# if any batch had no match, even when another batch did, which would hide hits).
attribution_hits=$(git ls-files -z ':!scripts/check-style.sh' | xargs -0 grep -nIEi "$attribution" 2>/dev/null || true)
if [ -n "$attribution_hits" ]; then
  printf '%s\n' "$attribution_hits"
  echo "STYLE GATE: forbidden AI-attribution or watermark above (github-discipline Rule 5.1)."
  fail=1
fi

# 2. Em dashes, changed files only (forward gate).
base="${1:-}"
if [ -n "$base" ]; then
  range="${base}...HEAD"
else
  range="--cached"
fi
while IFS= read -r changed; do
  [ -n "$changed" ] && [ -f "$changed" ] || continue
  if grep -nH -- "$emdash" "$changed"; then
    echo "STYLE GATE: em dash in changed file ${changed} (github-discipline Rule 5.2)."
    fail=1
  fi
done < <(git diff --name-only "$range" -- '*.md' '*.swift' '*.mjs' '*.js' '*.sh' '*.yml' '*.yaml')

if [ "$fail" -ne 0 ]; then
  echo "style gate: FAILED"
  exit 1
fi
echo "style gate: clean"
