#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app_bundle="$repo_root/.build/release/GlanceBar.app"
info_plist="$repo_root/Packaging/Info.plist"
resources_dir="$app_bundle/Contents/Resources"
frameworks_dir="$app_bundle/Contents/Frameworks"
sparkle_framework="$repo_root/.build/release/Sparkle.framework"
icon_info_plist="$repo_root/.build/release/GlanceBarIcon-Info.plist"

swift build -c release --package-path "$repo_root"
rm -rf "$app_bundle"
mkdir -p "$app_bundle/Contents/MacOS" "$resources_dir" "$frameworks_dir"
cp "$repo_root/.build/release/GlanceBar" "$app_bundle/Contents/MacOS/GlanceBar"
ditto "$sparkle_framework" "$frameworks_dir/Sparkle.framework"
cp "$info_plist" "$app_bundle/Contents/Info.plist"
rm -f "$icon_info_plist"
xcrun actool "$repo_root/Packaging/GlanceBar.icon" \
  --compile "$resources_dir" \
  --platform macosx \
  --minimum-deployment-target "$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$info_plist")" \
  --app-icon GlanceBar \
  --bundle-identifier "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$info_plist")" \
  --output-partial-info-plist "$icon_info_plist"
/usr/libexec/PlistBuddy -c "Merge $icon_info_plist" "$app_bundle/Contents/Info.plist"
rm -f "$icon_info_plist"
xcrun swift "$repo_root/Scripts/render-dmg-background.swift" "$resources_dir/dmg-background.png"
echo "$app_bundle"
