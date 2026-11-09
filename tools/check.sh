#!/usr/bin/env bash
# Totemic Accord - run all static checks (Linux/macOS, or Git Bash on Windows).
#
# Three checks, in order:
#   1. luac5.1 -p     syntax, against the same Lua version WoW runs
#   2. check_api.py   every API we call exists on Forever
#   3. luacheck       accidental globals, unused locals, undefined API
#                     (fed the generated Forever API surface via .luacheckrc)
#
# Usage: tools/check.sh [--fix]
set -uo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo"

FIX=0
[ "${1:-}" = "--fix" ] && FIX=1

have() { command -v "$1" >/dev/null 2>&1; }

# Pick a Lua 5.1 compiler under any of its usual names.
LUAC=""
for c in luac5.1 luac-5.1 luac; do
  if have "$c"; then
    if "$c" -v 2>&1 | grep -q "5\.1"; then LUAC="$c"; break; fi
  fi
done

PYTHON=""
for c in python3 python; do have "$c" && { PYTHON="$c"; break; }; done

# No mapfile: macOS still ships bash 3.2.
LUA_FILES=()
while IFS= read -r f; do LUA_FILES+=("$f"); done < <(find TotemicAccord -name "*.lua" -not -path "*/Libs/*" | sort)

failures=()

echo
echo "=== 1/3  Lua 5.1 syntax (luac -p) ==="
if [ -z "$LUAC" ]; then
  echo "  SKIPPED - no Lua 5.1 compiler found"
elif [ ${#LUA_FILES[@]} -eq 0 ]; then
  echo "  nothing to check yet"
else
  bad=0
  for f in "${LUA_FILES[@]}"; do
    if ! out=$("$LUAC" -p "$f" 2>&1); then
      echo "  FAIL $f"
      echo "$out" | sed 's/^/       /'
      bad=1
    fi
  done
  [ $bad -eq 1 ] && failures+=("luac -p") || echo "  OK - ${#LUA_FILES[@]} file(s)"
fi

echo
echo "=== 2/3  Forever API allowlist (check_api.py) ==="
if [ -z "$PYTHON" ]; then
  echo "  SKIPPED - python not found"
elif [ ! -d "reference/wow-ui-source/Interface" ]; then
  echo "  SKIPPED - reference/wow-ui-source missing. Clone it with:"
  echo "    git clone --depth 1 --branch forever https://github.com/Gethe/wow-ui-source reference/wow-ui-source"
else
  # Regenerate the globals list so .luacheckrc lints against current Forever.
  "$PYTHON" tools/check_api.py --emit-luacheck tools/wow_globals.lua || failures+=("check_api --emit-luacheck")
  "$PYTHON" tools/check_api.py || failures+=("check_api")
fi

echo
echo "=== 3/3  luacheck ==="
if ! have luacheck; then
  echo "  SKIPPED - luacheck not found"
elif [ ${#LUA_FILES[@]} -eq 0 ]; then
  echo "  nothing to check yet"
else
  if [ ! -f tools/wow_globals.lua ]; then
    echo "  NOTE: tools/wow_globals.lua missing - .luacheckrc is falling back to"
    echo "        its small curated API list, so API coverage is incomplete."
  fi
  luacheck "${LUA_FILES[@]}" || failures+=("luacheck")
fi

if [ $FIX -eq 1 ] && [ ${#LUA_FILES[@]} -gt 0 ]; then
  echo
  echo "=== format (StyLua) ==="
  if have stylua; then stylua "${LUA_FILES[@]}" && echo "  formatted"; else echo "  SKIPPED - stylua not found"; fi
fi

echo
if [ ${#failures[@]} -gt 0 ]; then
  echo "CHECK FAILED: ${failures[*]}"
  exit 1
fi
echo "ALL CHECKS PASSED"
