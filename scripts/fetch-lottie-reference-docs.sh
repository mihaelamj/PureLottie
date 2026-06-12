#!/usr/bin/env bash
# Refresh vendored official Lottie format documentation under docs/lottie-format/.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REF="$ROOT/docs/lottie-format"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

clone_and_copy() {
  local url="$1"
  local name="$2"
  shift 2
  git clone --depth 1 "$url" "$TMP/$name"
  mkdir -p "$REF/$name"
  for path in "$@"; do
    if [[ -e "$TMP/$name/$path" ]]; then
      rm -rf "$REF/$name/$(basename "$path")"
      cp -R "$TMP/$name/$path" "$REF/$name/"
    fi
  done
  git -C "$TMP/$name" rev-parse HEAD > "$REF/$name/SOURCE_COMMIT"
  git -C "$TMP/$name" log -1 --format=%ci >> "$REF/$name/SOURCE_COMMIT"
}

clone_and_copy https://github.com/lottie/lottie-spec.git lottie-spec \
  README.md License.md Community_Specification_License-v1.md Notices.md docs schema

clone_and_copy https://github.com/LottieFiles/lottie-docs.git lottie-docs \
  README.md COPYING docs schema

echo "Updated docs/lottie-format (lottie-spec + lottie-docs)."
