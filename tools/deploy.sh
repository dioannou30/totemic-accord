#!/usr/bin/env bash
# Deploy Totemic Accord into the WoW Forever AddOns folder (Linux/macOS).
#
# Copy mode (default) mirrors TotemicAccord/ into
#   <WOW_DIR>/_forever_/Interface/AddOns/TotemicAccord
# deleting stale files. --link symlinks instead, so edits are live after /reload.
#
# WOW_DIR comes from tools/deploy.local (gitignored). If missing, likely installs
# are autodetected and you are asked to confirm one, which is then saved.
#
# Usage: tools/deploy.sh [--link] [--check] [--force] [--wow-dir PATH]
set -uo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
addon_name="TotemicAccord"
flavor="_forever_"
source_dir="$repo/$addon_name"
local_file="$repo/tools/deploy.local"

LINK=0; CHECK=0; FORCE=0; WOW_OVERRIDE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --link) LINK=1 ;;
    --check) CHECK=1 ;;
    --force) FORCE=1 ;;
    --wow-dir) shift; WOW_OVERRIDE="${1:-}" ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

[ -d "$source_dir" ] || { echo "Addon folder not found: $source_dir" >&2; exit 1; }

if [ $CHECK -eq 1 ]; then
  echo "Running static checks first..."
  "$repo/tools/check.sh" || { echo "Checks failed - not deploying." >&2; exit 1; }
fi

save_local() {
  cat > "$local_file" <<EOF
# Local deploy configuration for Totemic Accord. Gitignored - machine specific.
# Path to the World of Warcraft folder that contains the $flavor directory.
WOW_DIR=$1
EOF
  echo "Saved WOW_DIR to $local_file"
}

read_local() {
  [ -f "$local_file" ] || return 1
  sed -n 's/^[[:space:]]*WOW_DIR[[:space:]]*=[[:space:]]*//p' "$local_file" | head -1
}

wow="$WOW_OVERRIDE"
[ -z "$wow" ] && wow="$(read_local || true)"

if [ -z "$wow" ]; then
  echo "No $local_file found - looking for a WoW install..."
  candidates=()
  while IFS= read -r p; do [ -n "$p" ] && candidates+=("$p"); done < <(
    for base in \
      "$HOME/Games/battlenet/drive_c/Program Files (x86)/World of Warcraft" \
      "$HOME/.wine/drive_c/Program Files (x86)/World of Warcraft" \
      "$HOME/Games/world-of-warcraft/drive_c/Program Files (x86)/World of Warcraft" \
      "/Applications/World of Warcraft" \
      "$HOME/.local/share/Steam/steamapps/compatdata"/*/pfx/drive_c/"Program Files (x86)/World of Warcraft" \
      "$HOME/.steam/steam/steamapps/compatdata"/*/pfx/drive_c/"Program Files (x86)/World of Warcraft" ; do
      [ -d "$base" ] && echo "$base"
    done
  )
  if [ ${#candidates[@]} -eq 0 ]; then
    cat >&2 <<EOF
Could not find a World of Warcraft folder automatically.
Create $local_file with the path, for example:

    WOW_DIR=/home/you/Games/battlenet/drive_c/Program Files (x86)/World of Warcraft

(That folder is the one containing the $flavor directory.)
EOF
    exit 1
  fi
  echo
  echo "Found these candidates:"
  i=1
  for c in "${candidates[@]}"; do
    if [ -d "$c/$flavor" ]; then mark="has $flavor"; else mark="NO $flavor"; fi
    echo "  [$i] $c  ($mark)"
    i=$((i+1))
  done
  echo
  printf 'Which one? [1-%d], or paste a path: ' "${#candidates[@]}"
  read -r answer
  if [[ "$answer" =~ ^[0-9]+$ ]] && [ "$answer" -ge 1 ] && [ "$answer" -le "${#candidates[@]}" ]; then
    wow="${candidates[$((answer-1))]}"
  elif [ -n "$answer" ]; then
    wow="$answer"
  else
    echo "No selection made." >&2; exit 1
  fi
  save_local "$wow"
elif [ ! -f "$local_file" ]; then
  save_local "$wow"
fi

[ -d "$wow" ] || { echo "WOW_DIR does not exist: $wow" >&2; exit 1; }

flavor_dir="$wow/$flavor"
if [ ! -d "$flavor_dir" ]; then
  echo "$flavor not found in: $wow" >&2
  echo >&2
  echo "Flavor folders that ARE there:" >&2
  found=$(find "$wow" -maxdepth 1 -type d -name '_*_' -printf '  %f\n' 2>/dev/null)
  echo "${found:-  (none)}" >&2
  echo >&2
  echo "Totemic Accord targets WoW Forever, which installs as $flavor." >&2
  echo "Point WOW_DIR at the right install in $local_file." >&2
  exit 1
fi

addons_dir="$flavor_dir/Interface/AddOns"
target="$addons_dir/$addon_name"
[ -d "$addons_dir" ] || { mkdir -p "$addons_dir"; echo "Created $addons_dir"; }

echo
if [ $LINK -eq 1 ]; then
  if [ -L "$target" ]; then
    rm -f "$target"
  elif [ -d "$target" ]; then
    n=$(find "$target" -type f | wc -l)
    echo "The target is a REAL folder with $n file(s):"
    echo "  $target"
    echo "Link mode must delete it and put a symlink in its place."
    if [ $FORCE -eq 0 ]; then
      printf 'Delete it and replace with a symlink? [y/N] '
      read -r ok
      case "$ok" in y|Y|yes|YES) ;; *) echo "Aborted."; exit 1 ;; esac
    fi
    rm -rf "$target"
  fi
  ln -s "$source_dir" "$target"
  echo "LINKED (symlink)"
  echo "  $target"
  echo "  -> $source_dir"
  mode=link
else
  if [ -L "$target" ]; then
    echo "Target is currently a symlink; removing it to copy instead."
    rm -f "$target"
  fi
  mkdir -p "$target"
  if command -v rsync >/dev/null 2>&1; then
    rsync -a --delete "$source_dir/" "$target/"
  else
    echo "rsync not found - falling back to rm -rf + cp -a"
    rm -rf "$target"
    cp -a "$source_dir" "$target"
  fi
  echo "COPIED (mirrored)"
  echo "  $source_dir"
  echo "  -> $target  ($(find "$target" -type f | wc -l) file(s))"
  mode=copy
fi

echo
echo "In game:"
echo "  Lua/XML changes  -> /reload is enough"
echo "  NEW files or TOC changes -> fully restart the game client"
if [ "$mode" = copy ]; then
  echo "  (copy mode: re-run this script after every change)"
else
  echo "  (link mode: edits are live, just /reload)"
fi
echo
echo "Tip: /console scriptErrors 1   shows Lua errors in game"
