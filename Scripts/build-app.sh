#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app_bundle="$repo_root/.build/release/GlanceBar.app"

swift build -c release --package-path "$repo_root"
rm -rf "$app_bundle"
mkdir -p "$app_bundle/Contents/MacOS" "$app_bundle/Contents/Resources"
cp "$repo_root/.build/release/GlanceBar" "$app_bundle/Contents/MacOS/GlanceBar"
cp "$repo_root/Packaging/Info.plist" "$app_bundle/Contents/Info.plist"
echo "$app_bundle"
