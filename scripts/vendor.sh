#!/usr/bin/env bash
# Exports the local bixverse checkouts into vendor/, so the image and the
# native GPU run build unreleased versions without touching the working trees.
# REF_<pkg> picks the ref per package (dots as underscores), default main,
# e.g. REF_bixverse=feat-better-sc-io.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
rm -rf "$root/vendor"; mkdir -p "$root/vendor"
for pkg in manifoldsR bixverse bixverse.gpu; do
  mkdir -p "$root/vendor/$pkg"
  var="REF_${pkg//./_}"
  ref="${!var:-main}"
  git -C ~/repos/shared/$pkg archive "$ref" | tar -x -C "$root/vendor/$pkg"
  echo "$pkg $ref $(git -C ~/repos/shared/$pkg rev-parse --short "$ref")" >> "$root/vendor/SHAS"
done
cat "$root/vendor/SHAS"
