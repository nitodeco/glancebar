#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app_bundle="${1:-"$repo_root/.build/release/GlanceBar.app"}"
signing_identity="${GLANCEBAR_SIGNING_IDENTITY:-}"

if [[ -z "$signing_identity" ]]; then
  echo "GLANCEBAR_SIGNING_IDENTITY is required" >&2
  exit 1
fi

codesign --force --deep --options runtime --timestamp --sign "$signing_identity" "$app_bundle"
codesign --verify --deep --strict --verbose=2 "$app_bundle"
