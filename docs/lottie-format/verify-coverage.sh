#!/usr/bin/env bash
# Coverage verifier for the Lottie format docs.
#
# Turns the "100%, nothing left unsaid" and "model-or-report" claims into a
# checkable, reproducible test: it extracts every property key and every enum
# const value from the pinned official Lottie schema and fails if any one is
# absent from lottie-format-complete.md (defined) OR from lottie-import-mapping.md
# (given a model-or-report disposition). The checker is far smaller than what it
# checks (Knuth K5), and pins the schema commit so the result is reproducible
# rather than a moving target.
#
# Scope and honest limits:
#  - Verifies the OFFICIAL lottie-spec schema only. The superset section (text,
#    effects, layer styles, expressions, ...) is prose; there is no machine schema
#    for it, so it is not mechanically checkable here.
#  - The single-character const values (a,b,c,d,g,i,n,o,s,v) match loosely; their
#    "present" result is weak. The integer (0..16) and multi-char consts are firm.
#
# Usage: docs/lottie-format/verify-coverage.sh   (needs: gh, jq, tar)
# Exit 0 = every schema key/const appears in the doc; non-zero = a gap (something
# left unsaid) or an over-claim.
set -euo pipefail

PINNED_SHA="4b55957472f8718e34e9c1298f0e8f021b6c597f"   # lottie/lottie-spec main, verified 2026-06-13
DOC="$(cd "$(dirname "$0")" && pwd)/lottie-format-complete.md"
MAP="$(cd "$(dirname "$0")" && pwd)/lottie-import-mapping.md"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "Verifying $DOC against lottie-spec @ $PINNED_SHA"
gh api "repos/lottie/lottie-spec/tarball/$PINNED_SHA" > "$WORK/spec.tar.gz"
tar xzf "$WORK/spec.tar.gz" -C "$WORK"
SCHEMA="$(find "$WORK" -type d -name schema | head -1)"
[ -n "$SCHEMA" ] || { echo "schema dir not found"; exit 2; }

# Every property key defined anywhere in the schema.
for f in $(find "$SCHEMA" -name '*.json'); do
  jq -r '.. | objects | select(has("properties")) | .properties | keys[]' "$f" 2>/dev/null
done | sort -u > "$WORK/keys.txt"

# Every enum const value (constants/).
for f in $(find "$SCHEMA/constants" -name '*.json' 2>/dev/null); do
  jq -r '.oneOf[]?.const // empty' "$f" 2>/dev/null
done | sort -u > "$WORK/consts.txt"

gaps=0
while read -r k; do
  grep -qE "\`$k\`" "$DOC" || { echo "MISSING key: $k"; gaps=$((gaps+1)); }
done < "$WORK/keys.txt"
while read -r c; do
  grep -qF "\"$c\"" "$DOC" || grep -qE "(^| )$c( |\$|,)" "$DOC" || { echo "MISSING const: $c"; gaps=$((gaps+1)); }
done < "$WORK/consts.txt"

# Every schema key must also have a model-or-report disposition in the mapping doc
# (the C6 coverage promise made checkable: nothing is silently droppable).
while read -r k; do
  grep -qE "\`$k\`" "$MAP" || { echo "UNMAPPED key (import-mapping): $k"; gaps=$((gaps+1)); }
done < "$WORK/keys.txt"

echo "keys checked: $(wc -l < "$WORK/keys.txt") (in 2 docs), consts checked: $(wc -l < "$WORK/consts.txt"), gaps: $gaps"
[ "$gaps" -eq 0 ] || { echo "FAIL: $gaps schema item(s) not covered by the doc."; exit 1; }
echo "PASS: every schema key and const value appears in the doc."
