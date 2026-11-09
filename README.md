# Totemic Accord

A themed shaman totem bar for **World of Warcraft: Forever** (client 1.60.1, interface
16001), with profiles that switch **automatically by spec and situation**.

> Status: **M1 (skeleton) built, awaiting in-game verification.** It loads, gates on class,
> creates saved variables and answers `/ta` and `/ta selftest`. No bar yet.
> See `docs/CLAUDE_CODE_PROMPT.md` for the full spec and `docs/decisions.md` for the log.

Other Forever totem bars exist; none of them switches totem sets automatically by
**spec × instance type**. That, the per-profile sequence builder, and the theming are the
point of this one.

## What it will do

- **Seven buttons:** Earth, Fire, Water, Air, Action, Totemic Projection, Profile chooser.
- **Profiles by spec × situation** (open world, dungeon, raid, battleground, arena) with a
  clean fallback chain: `spec:situation` → `spec:default` → `global` → captured native bar.
  Switches are queued during combat and applied when it ends.
- **A per-profile castsequence** button that becomes **Call of the Elements** once learned.
- **Flyouts** per element to change the active profile's totem (mouse only — OPie stays
  the keyboard flyout).
- **Five themes** (Emerald, Tokyo Night, Catppuccin Mocha, Catppuccin Latte, Blizzard
  classic), initials-or-icons buttons, three layouts, all switchable without a `/reload`.

The interactive visual reference is `docs/mock/totemic-accord-mock.html` — open it in a
browser; it is the source of truth for look and behaviour.

## Requirements

| | |
|---|---|
| Game | WoW Forever, installed as a `_forever_` flavor folder |
| Class | Shaman (the addon disables itself quietly otherwise) |
| Dev tools | git; Lua 5.1 and luacheck recommended; Python 3 for the API linter |

## Deploying

```powershell
.\tools\deploy.ps1            # mirror into the WoW AddOns folder
.\tools\deploy.ps1 -Check     # run static checks first, stop on failure
.\tools\deploy.ps1 -Link      # junction instead of copy, so edits are live
```

Linux/macOS: `tools/deploy.sh`, same flags as `--link` / `--check`.

The first run autodetects your WoW folder, asks you to confirm, and saves the choice to
`tools/deploy.local` (gitignored). To set it by hand, copy `tools/deploy.local.example`:

```
WOW_DIR=D:\World of Warcraft
```

That is the folder **containing** `_forever_` — not `_forever_` itself.

**After deploying:** Lua and XML changes need `/reload` in game. **New files or TOC changes
need a full game restart.** Copy mode means re-running the script after each change; link
mode means edits are live.

## Checking

```powershell
.\tools\check.ps1             # luac -p, API allowlist, luacheck
.\tools\check.ps1 -Fix        # also run StyLua
```

Three checks, in order:

1. **`luac5.1 -p`** — syntax, against the same Lua version WoW runs.
2. **`tools/check_api.py`** — every API we call actually exists on Forever.
3. **`luacheck`** — accidental globals, unused locals, undefined API.

There is also an offline smoke test that stubs the WoW API and drives the addon in plain
Lua 5.1 — lifecycle hooks, every slash command, the self-test, and the non-Shaman path:

```bash
lua5.1 tools/smoke.lua
```

It proves the code runs without launching the game. It is not a substitute for
`docs/testing.md`, and it is deliberately not part of `tools/check`.

The API surface is not hardcoded anywhere. `check_api.py` extracts it from Blizzard's own
UI source and writes `tools/wow_globals.lua`, which `.luacheckrc` loads — so one source of
truth feeds both the linter and luacheck. That needs the reference clone:

```bash
git clone --depth 1 --branch forever https://github.com/Gethe/wow-ui-source reference/wow-ui-source
```

Both `reference/` and the generated `tools/wow_globals.lua` are gitignored. Re-clone after
a game patch so the allowlist tracks the live API.

## Testing in game

`docs/testing.md` has a checklist per milestone and records the **VERIFY** answers that
later work depends on. Turn on Lua errors first:

```
/console scriptErrors 1
```

## Sharing with friends

```powershell
.\tools\package.ps1           # dist/TotemicAccord-<version>.zip
```

Version comes from the `## Version:` line of the TOC. They extract so the folder lands at
`<WoW>\_forever_\Interface\AddOns\TotemicAccord`.

## Layout

```
docs/          spec, decisions log, test checklists, visual mock
tools/         deploy, check, package, API allowlist linter
reference/     gitignored: Blizzard's UI source for Forever (API source of truth)
TotemicAccord/ the addon folder that gets deployed
  Libs/        vendored libraries, pinned (see Libs/VERSIONS.md)
  media/fonts/ Manrope + JetBrains Mono (SIL OFL)
```

## Licensing

Vendored libraries keep their own licenses (`TotemicAccord/Libs/`), and the bundled fonts
are SIL Open Font License with their `OFL.txt` alongside. `TotemicAccord/Libs/VERSIONS.md`
records every pin and where it came from.
