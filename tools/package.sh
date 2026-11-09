#!/usr/bin/env bash
# Zip TotemicAccord/ into dist/TotemicAccord-<version>.zip for sharing.
# Version comes from the ## Version line of the TOC, the single source of truth.
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
addon_name="TotemicAccord"
toc="$repo/$addon_name/$addon_name.toc"

version="${1:-}"
if [ -z "$version" ]; then
  [ -f "$toc" ] || { echo "TOC not found: $toc" >&2; exit 1; }
  version=$(sed -n 's/^##[[:space:]]*Version:[[:space:]]*//p' "$toc" | head -1 | tr -d '\r')
  [ -n "$version" ] || { echo "No '## Version:' line in $toc" >&2; exit 1; }
fi

mkdir -p "$repo/dist"
zip_path="$repo/dist/$addon_name-$version.zip"
rm -f "$zip_path"

# Zip from the repo root so the archive contains a single TotemicAccord/ folder.
( cd "$repo" && zip -qr "$zip_path" "$addon_name" )

echo "Packaged $addon_name $version"
echo "  $zip_path  ($(du -h "$zip_path" | cut -f1))"
echo
echo "Tell your friends: extract so the folder lands at"
echo "  <WoW>/_forever_/Interface/AddOns/$addon_name"
