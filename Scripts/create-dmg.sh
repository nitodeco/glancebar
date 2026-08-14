#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app_bundle="${1:-"$repo_root/.build/release/GlanceBar.app"}"
dist_dir="$repo_root/dist"
dmg_contents="$repo_root/.build/release/dmg"
dmg_path="$dist_dir/GlanceBar.dmg"
signing_identity="${GLANCEBAR_SIGNING_IDENTITY:-}"

cleanup() {
  rm -rf "$dmg_contents"
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
rm -f "$dmg_path"
hdiutil create -volname GlanceBar -srcfolder "$dmg_contents" -ov -format UDZO "$dmg_path" >/dev/null
codesign --force --timestamp --sign "$signing_identity" "$dmg_path"
codesign --verify --strict --verbose=2 "$dmg_path"
echo "$dmg_path"
