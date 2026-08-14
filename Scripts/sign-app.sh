#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app_bundle="${1:-"$repo_root/.build/release/GlanceBar.app"}"
signing_identity="${GLANCEBAR_SIGNING_IDENTITY:-}"
sparkle_framework="$app_bundle/Contents/Frameworks/Sparkle.framework"

if [[ -z "$signing_identity" ]]; then
  echo "GLANCEBAR_SIGNING_IDENTITY is required" >&2
  exit 1
fi

codesign --force --options runtime --timestamp --sign "$signing_identity" \
  "$sparkle_framework/Versions/B/XPCServices/Installer.xpc"
codesign --force --options runtime --timestamp --preserve-metadata=entitlements --sign "$signing_identity" \
  "$sparkle_framework/Versions/B/XPCServices/Downloader.xpc"
codesign --force --options runtime --timestamp --sign "$signing_identity" \
  "$sparkle_framework/Versions/B/Autoupdate"
codesign --force --options runtime --timestamp --sign "$signing_identity" \
  "$sparkle_framework/Versions/B/Updater.app"
codesign --force --options runtime --timestamp --sign "$signing_identity" "$sparkle_framework"
codesign --force --options runtime --timestamp --sign "$signing_identity" "$app_bundle"
codesign --verify --deep --strict --verbose=2 "$app_bundle"
