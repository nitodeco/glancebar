#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app_bundle="$repo_root/.build/release/GlanceBar.app"
dist_dir="$repo_root/dist"

"$repo_root/Scripts/build-app.sh" >/dev/null
"$repo_root/Scripts/sign-app.sh" "$app_bundle" >/dev/null
rm -rf "$dist_dir"
mkdir -p "$dist_dir"
"$repo_root/Scripts/create-dmg.sh" "$app_bundle"
