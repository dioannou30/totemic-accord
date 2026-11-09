#!/usr/bin/env python3
"""
Totemic Accord - API allowlist linter.

WoW Forever (client 1.60.1, interface 16001) exposes its own API surface. Calling a
function that does not exist there fails at runtime, in game, usually mid-fight. This
script builds the set of APIs that Forever actually provides, straight out of Blizzard's
own UI source, and flags anything our addon calls that is not in that set.

Two modes:

  (default)            Scan TotemicAccord/ and report unknown globals / C_ calls / events.
  --emit-luacheck PATH Write the allowlist as a Lua file for .luacheckrc to consume, so
                       luacheck -- which understands real Lua scoping -- becomes the
                       rigorous backstop for this script's regex-based scan.

The allowlist comes from three places in reference/wow-ui-source:
  1. Blizzard_APIDocumentationGenerated/*.lua -- the generated API docs. Authoritative
     for C_ namespaces, global API functions, events and enums.
  2. Every other Blizzard .lua file -- for globals defined in Lua rather than by the
     engine (mixins, constants, FrameXML helper functions).
  3. Globals that Blizzard's own shipped UI calls or aliases. The generated docs are
     incomplete: CreateFrame, InCombatLockdown, SetMultiCastSpell,
     GetMultiCastTotemSpells, CreateMacro and SendAddonMessage are all absent from
     them, yet all exist. If Blizzard's UI calls a global on this client, it is real.

Source 3 makes the allowlist permissive -- it also picks up Blizzard's local helper
names. That is an accepted trade-off: the job here is catching INVENTED APIs, and a
hallucinated function name appears nowhere in Blizzard's source. luacheck, fed by
--emit-luacheck, is the strict check for our own code's scoping and stray globals.

Usage:
    python tools/check_api.py
    python tools/check_api.py --emit-luacheck tools/wow_globals.lua
    python tools/check_api.py --reference reference/wow-ui-source --addon TotemicAccord
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

# ---------------------------------------------------------------------------
# Lua 5.1 base library + the extras the WoW engine injects that are not
# declared anywhere in Blizzard's Lua source (so step 2 below cannot find them).
# ---------------------------------------------------------------------------

LUA51_BASE = {
    "assert", "collectgarbage", "dofile", "error", "getfenv", "getmetatable",
    "ipairs", "load", "loadfile", "loadstring", "module", "next", "pairs",
    "pcall", "print", "rawequal", "rawget", "rawlen", "rawset", "require",
    "select", "setfenv", "setmetatable", "tonumber", "tostring", "type",
    "unpack", "xpcall", "newproxy",
    "coroutine", "debug", "io", "math", "os", "package", "string", "table", "bit",
}

# WoW's Lua is extended with these; they are engine-provided globals.
WOW_LUA_EXTRAS = {
    # string helpers
    "strsplit", "strjoin", "strconcat", "strtrim", "strlen", "strlower",
    "strupper", "strrep", "strsub", "strbyte", "strchar", "strfind",
    "strmatch", "strrev", "gsub", "gmatch", "format",
    # table helpers
    "tinsert", "tremove", "tContains", "tIndexOf", "tDeleteItem", "tFilter",
    "tInvert", "wipe", "CopyTable", "MergeTable", "tCompare", "tAppendAll",
    "sort", "getn", "setn", "foreach", "foreachi",
    # math helpers
    "abs", "ceil", "floor", "max", "min", "mod", "sqrt", "random", "fastrandom",
    "PI", "huge",
    # mixin / misc engine globals
    "Mixin", "CreateFromMixins", "CreateAndInitFromMixin", "securecall",
    "issecure", "issecurevariable", "hooksecurefunc", "scrub", "seterrorhandler",
    "geterrorhandler", "debugstack", "debugprofilestart", "debugprofilestop",
    "time", "date", "difftime", "bit", "Enum", "Constants",
    "LE_EXPANSION_LEVEL_CURRENT", "WOW_PROJECT_ID",
}

# Globals our own addon is allowed to define. Keep this list short on purpose:
# every entry is a global we are deliberately adding to the shared namespace.
OWN_GLOBALS = {
    "TotemicAccord",                 # addon namespace / LibStub-style access
    "TotemicAccordDB",               # SavedVariables (account)
    "TotemicAccordCharDB",           # SavedVariablesPerCharacter
    # TOC AddonCompartment handlers must be globals -- the only allowed extras.
    "TotemicAccord_OnAddonCompartmentClick",
    "TotemicAccord_OnAddonCompartmentEnter",
    "TotemicAccord_OnAddonCompartmentLeave",
    # Binding headers / names referenced from Bindings.xml
    "BINDING_HEADER_TOTEMICACCORD",
}

# ---------------------------------------------------------------------------
# Patterns
# ---------------------------------------------------------------------------

# { Name = "Foo", \n Type = "Function"
RE_DOC_FUNCTION = re.compile(
    r'Name\s*=\s*"([A-Za-z0-9_]+)"\s*,\s*\n\s*Type\s*=\s*"Function"'
)
RE_DOC_NAMESPACE = re.compile(r'Namespace\s*=\s*"([A-Za-z0-9_]+)"')
RE_DOC_EVENT = re.compile(r'LiteralName\s*=\s*"([A-Z0-9_]+)"')
RE_DOC_ENUM = re.compile(
    r'Name\s*=\s*"([A-Za-z0-9_]+)"\s*,\s*\n\s*Type\s*=\s*"(?:Enumeration|Constants)"'
)

# Globals defined in Blizzard's Lua: `function Foo(`, `function Ns.Foo(`, `FOO = `
RE_LUA_GLOBAL_FUNC = re.compile(r'^\s*function\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(', re.M)
RE_LUA_GLOBAL_METHOD = re.compile(
    r'^\s*function\s+([A-Za-z_][A-Za-z0-9_]*)[.:][A-Za-z0-9_]+\s*\(', re.M
)
RE_LUA_GLOBAL_ASSIGN = re.compile(
    r'^([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(?!=)', re.M
)

# Undocumented engine functions: the generated docs do not cover everything the
# client exposes (CreateFrame, InCombatLockdown, SetMultiCastSpell,
# GetMultiCastTotemSpells, CreateMacro ... are all absent from them). But if
# Blizzard's own shipped UI calls or aliases a global on this client, it exists.
# That makes Blizzard's Lua a third, grounded source for the allowlist.
RE_LUA_CALLED_GLOBAL = re.compile(r'(?<![:.\w])([A-Z][A-Za-z0-9_]*)\s*\(')
RE_LUA_ALIASED_GLOBAL = re.compile(r'=\s*([A-Z][A-Za-z0-9_]*)\s*;')

# Call sites in our code.
RE_CALL_GLOBAL = re.compile(r'(?<![:.\w])([A-Z][A-Za-z0-9_]*)\s*\(')
RE_CALL_NAMESPACED = re.compile(r'(?<![:.\w])(C_[A-Za-z0-9_]+)\.([A-Za-z0-9_]+)\s*\(')
RE_REGISTER_EVENT = re.compile(r'RegisterEvent\w*\s*\(\s*"([A-Z0-9_]+)"')

# Local declarations in our code, so we do not flag our own locals.
RE_LOCAL = re.compile(r'\blocal\s+(?:function\s+)?([A-Za-z_][A-Za-z0-9_,\s]*)')
RE_OWN_METHOD = re.compile(r'^\s*function\s+[A-Za-z_][A-Za-z0-9_]*[.:]([A-Za-z0-9_]+)', re.M)


class Allowlist:
    def __init__(self) -> None:
        self.globals: set[str] = set()      # bare global functions/tables
        self.namespaces: dict[str, set[str]] = {}  # C_Foo -> {Bar, Baz}
        self.events: set[str] = set()
        self.enums: set[str] = set()

    def all_global_names(self) -> set[str]:
        return self.globals | set(self.namespaces)


def read_text(path: Path) -> str:
    # Blizzard source is mostly UTF-8 but has stray latin-1 bytes in places.
    return path.read_text(encoding="utf-8", errors="replace")


def build_allowlist(reference: Path) -> Allowlist:
    allow = Allowlist()
    iface = reference / "Interface"
    if not iface.is_dir():
        sys.exit(
            f"error: {iface} not found.\n"
            "       Clone the reference first:\n"
            "       git clone --depth 1 --branch forever "
            "https://github.com/Gethe/wow-ui-source reference/wow-ui-source"
        )

    doc_dir = iface / "AddOns" / "Blizzard_APIDocumentationGenerated"
    doc_files = sorted(doc_dir.glob("*.lua")) if doc_dir.is_dir() else []

    # 1. Generated API documentation -- authoritative.
    for path in doc_files:
        text = read_text(path)
        ns_match = RE_DOC_NAMESPACE.search(text)
        funcs = set(RE_DOC_FUNCTION.findall(text))
        if ns_match:
            ns = ns_match.group(1)
            allow.namespaces.setdefault(ns, set()).update(funcs)
            # A namespaced system very often ALSO keeps a legacy bare global
            # alias (GetSpecialization is documented under C_SpecializationInfo
            # but is a plain global in game, as the build prompt confirms). The
            # docs carry no flag for that, so accept both spellings.
            allow.globals.update(funcs)
        else:
            allow.globals.update(funcs)
        allow.events.update(RE_DOC_EVENT.findall(text))
        allow.enums.update(RE_DOC_ENUM.findall(text))

    # 2. Globals defined in Blizzard's own Lua (mixins, constants, helpers).
    for path in iface.rglob("*.lua"):
        if path.parent.name == "Blizzard_APIDocumentationGenerated":
            continue
        text = read_text(path)
        allow.globals.update(RE_LUA_GLOBAL_FUNC.findall(text))
        allow.globals.update(RE_LUA_GLOBAL_METHOD.findall(text))
        allow.globals.update(RE_LUA_GLOBAL_ASSIGN.findall(text))
        # 3. Undocumented engine globals, evidenced by Blizzard's own use.
        allow.globals.update(RE_LUA_CALLED_GLOBAL.findall(text))
        allow.globals.update(RE_LUA_ALIASED_GLOBAL.findall(text))

    # Frame/widget XML names are globals too (templates with name="Foo").
    for path in iface.rglob("*.xml"):
        text = read_text(path)
        allow.globals.update(re.findall(r'\bname="([A-Za-z_][A-Za-z0-9_]*)"', text))

    allow.globals -= {"local", "function", "return", "end", "then", "else"}
    return allow


def addon_lua_files(addon: Path) -> list[Path]:
    return sorted(
        p for p in addon.rglob("*.lua")
        if "Libs" not in p.relative_to(addon).parts
    )


def scan_addon(addon: Path, allow: Allowlist) -> list[str]:
    """Report call sites our allowlist does not cover. Regex-based, so it is
    deliberately conservative: only CamelCase identifiers are considered, and
    anything declared locally in the same file is skipped. luacheck (fed by
    --emit-luacheck) is the rigorous check; this is the fast, dependency-free one."""
    problems: list[str] = []
    known_globals = (
        allow.all_global_names() | LUA51_BASE | WOW_LUA_EXTRAS | OWN_GLOBALS
    )

    for path in addon_lua_files(addon):
        text = read_text(path)
        rel = path.relative_to(addon.parent).as_posix()

        # Names that are local to this file, so not API calls.
        local_names: set[str] = set()
        for group in RE_LOCAL.findall(text):
            for name in group.split(","):
                name = name.strip()
                if name:
                    local_names.add(name)
        local_names.update(RE_OWN_METHOD.findall(text))

        lines = text.splitlines()
        for lineno, line in enumerate(lines, start=1):
            code = line.split("--", 1)[0]
            if not code.strip():
                continue

            for name in RE_CALL_GLOBAL.findall(code):
                if name in known_globals or name in local_names:
                    continue
                problems.append(
                    f"{rel}:{lineno}: unknown global call '{name}(' "
                    f"-- not in the Forever API surface"
                )

            for ns, fn in RE_CALL_NAMESPACED.findall(code):
                if ns not in allow.namespaces:
                    problems.append(f"{rel}:{lineno}: unknown namespace '{ns}'")
                elif fn not in allow.namespaces[ns]:
                    problems.append(
                        f"{rel}:{lineno}: '{ns}.{fn}' does not exist on Forever"
                    )

            for event in RE_REGISTER_EVENT.findall(code):
                if allow.events and event not in allow.events:
                    problems.append(
                        f"{rel}:{lineno}: unknown event '{event}' "
                        f"-- not documented on Forever"
                    )

    return problems


def emit_luacheck(allow: Allowlist, out: Path) -> None:
    """Write the allowlist as a Lua file returning a read_globals table, so
    .luacheckrc can hand luacheck the real Forever API surface."""
    # Namespace names are deliberately NOT emitted as plain globals: they get a
    # field-restricted definition below instead. Emitting both would make the
    # unrestricted entry win, and C_Spell.NoSuchFunction() would slip through.
    names = sorted((allow.globals | WOW_LUA_EXTRAS) - set(allow.namespaces))
    lines = [
        "-- GENERATED by tools/check_api.py -- do not edit by hand.",
        "-- The WoW Forever API surface, extracted from reference/wow-ui-source.",
        "-- Regenerate with: python tools/check_api.py --emit-luacheck tools/wow_globals.lua",
        "local globals = {",
    ]
    for name in names:
        lines.append(f'\t"{name}",')
    lines.append("}")
    lines.append("")
    lines.append("local namespaces = {")
    for ns in sorted(allow.namespaces):
        fields = ", ".join(f'"{f}"' for f in sorted(allow.namespaces[ns]))
        lines.append(f"\t[{ns!r}] = {{ {fields} }},".replace("'", '"'))
    lines.append("}")
    lines.append("")
    lines.append("return { globals = globals, namespaces = namespaces }")
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> int:
    repo = Path(__file__).resolve().parent.parent
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--reference", default=str(repo / "reference" / "wow-ui-source"))
    ap.add_argument("--addon", default=str(repo / "TotemicAccord"))
    ap.add_argument("--emit-luacheck", metavar="PATH",
                    help="write the allowlist as a Lua file for .luacheckrc")
    ap.add_argument("--stats", action="store_true", help="print allowlist size and exit")
    args = ap.parse_args()

    allow = build_allowlist(Path(args.reference))

    if args.stats or args.emit_luacheck:
        ns_fns = sum(len(v) for v in allow.namespaces.values())
        print(
            f"Forever API surface: {len(allow.globals)} globals, "
            f"{len(allow.namespaces)} C_ namespaces ({ns_fns} functions), "
            f"{len(allow.events)} events, {len(allow.enums)} enums"
        )

    if args.emit_luacheck:
        out = Path(args.emit_luacheck)
        emit_luacheck(allow, out)
        print(f"wrote {out}")
        return 0

    addon = Path(args.addon)
    if not addon.is_dir():
        print(f"note: {addon} does not exist yet -- nothing to check.")
        return 0

    files = addon_lua_files(addon)
    if not files:
        print("note: no addon Lua files yet -- nothing to check.")
        return 0

    problems = scan_addon(addon, allow)
    if problems:
        print(f"check_api: {len(problems)} problem(s) found\n")
        for p in problems:
            print("  " + p)
        return 1

    print(f"check_api: OK -- {len(files)} file(s), no unknown API use.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
