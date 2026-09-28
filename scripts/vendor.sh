#!/usr/bin/env bash
# Exports the main branch of the local bixverse checkouts into vendor/, so the
# image and the native GPU run build unreleased versions without touching the
# working trees.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
rm -rf "$root/vendor"; mkdir -p "$root/vendor"
for pkg in bixverse bixverse.gpu; do
  mkdir -p "$root/vendor/$pkg"
  git -C ~/repos/shared/$pkg archive main | tar -x -C "$root/vendor/$pkg"
  echo "$pkg $(git -C ~/repos/shared/$pkg rev-parse --short main)" >> "$root/vendor/SHAS"
done
cat "$root/vendor/SHAS"
