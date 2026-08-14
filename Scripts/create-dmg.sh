#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app_bundle="${1:-"$repo_root/.build/release/GlanceBar.app"}"
dist_dir="$repo_root/dist"
dmg_contents="$repo_root/.build/release/dmg"
dmg_path="$dist_dir/GlanceBar.dmg"
writable_dmg_path="$repo_root/.build/release/GlanceBar-rw.dmg"
mount_dir="$(mktemp -d)"
signing_identity="${GLANCEBAR_SIGNING_IDENTITY:-}"
mounted_device=""

cleanup() {
  if [[ -n "$mounted_device" ]]; then
    hdiutil detach "$mounted_device" -force >/dev/null 2>&1 || true
  fi

  rm -rf "$mount_dir"
  rm -rf "$dmg_contents"
  rm -f "$writable_dmg_path"
}

trap cleanup EXIT

if [[ -z "$signing_identity" ]]; then
  echo "GLANCEBAR_SIGNING_IDENTITY is required" >&2
  exit 1
fi

rm -rf "$dmg_contents"
mkdir -p "$dmg_contents" "$dist_dir"
ditto "$app_bundle" "$dmg_contents/GlanceBar.app"
ln -s /Applications "$dmg_contents/Applications"

rm -f "$dmg_path" "$writable_dmg_path"
hdiutil create -volname GlanceBar -srcfolder "$dmg_contents" -ov -format UDRW -fs HFS+ "$writable_dmg_path" >/dev/null
hdiutil attach "$writable_dmg_path" -readwrite -noverify -noautoopen -mountpoint "$mount_dir" >/dev/null
mounted_device="$(df "$mount_dir" | awk 'NR == 2 { print $1 }')"

osascript <<EOF
tell application "Finder"
  set mountedDisk to POSIX file "$mount_dir" as alias
  open mountedDisk
  delay 1
  set installerWindow to container window of mountedDisk
  set current view of installerWindow to icon view
  set toolbar visible of installerWindow to false
  set statusbar visible of installerWindow to false
  set pathbar visible of installerWindow to false
  set sidebar width of installerWindow to 0
  set bounds of installerWindow to {100, 100, 760, 520}
  set iconOptions to icon view options of installerWindow
  set arrangement of iconOptions to not arranged
  set icon size of iconOptions to 128
  set text size of iconOptions to 14
  set background picture of iconOptions to file "GlanceBar.app:Contents:Resources:dmg-background.png" of mountedDisk
  set extension hidden of item "GlanceBar.app" of mountedDisk to true
  set position of item "GlanceBar.app" of mountedDisk to {175, 195}
  set position of item "Applications" of mountedDisk to {485, 195}
  update mountedDisk without registering applications
  delay 1
  close installerWindow
end tell
EOF

rm -rf "$mount_dir/.fseventsd"
sync
hdiutil detach "$mounted_device" >/dev/null
mounted_device=""
hdiutil convert "$writable_dmg_path" -format UDZO -o "$dmg_path" >/dev/null
codesign --force --timestamp --sign "$signing_identity" "$dmg_path"
codesign --verify --strict --verbose=2 "$dmg_path"
echo "$dmg_path"
