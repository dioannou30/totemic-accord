# Totemic Accord

**A shaman totem bar for World of Warcraft: Forever that swaps your totems for you.**

Set up which four totems you want for each talent loadout and each kind of content (open world,
dungeon, raid, battleground, arena). When you change loadout or zone, the bar switches to the
right set on its own. One key drops them all.

![Version](https://img.shields.io/badge/version-0.9.0-orange)
![Client](https://img.shields.io/badge/WoW%20Forever-1.60.1%20(16001)-blue)
![Class](https://img.shields.io/badge/class-Shaman-0070DD)

## Features

- **Automatic totem profiles** by talent loadout and situation, with a clear fallback order and
  a manual pin when you want to override it.
- **One button for all four totems:** a cast sequence before level 20, then **Call of the
  Elements**, fed with the active profile's totems.
- **Totem chooser** on every element button (right-click), plus **Totemic Recall** on the bar.
- **Active-totem outline:** a button lights up while its totem is on the ground.
- **Keybinds** set from the options or the game's Key Bindings menu, with one-click suggestions.
- **Four themes** (Emerald, Tokyo Night, Catppuccin Mocha, Blizzard classic), three layouts,
  initials or icons, scale, spacing and opacity.
- **Share setups** with friends as a `TA1:` text string.
- **Hide the default totem bar** if you only want this one.
- Combat-safe: anything the game blocks mid-fight waits and applies when combat ends.

> **Status: 0.9.0.** Everything above is built and checked in game, except Call of the Elements
> itself (it needs a level 20 shaman). If you hit a problem, open an issue with the output of
> `/ta selftest`.

## Installing

1. Download `TotemicAccord-0.9.0.zip` from the
   [Releases](https://github.com/dioannou30/totemic-accord/releases) page.
   Don't use GitHub's green **Code → Download ZIP** button: that gives you the whole project,
   not the addon folder.
2. Extract it so the folder lands at
   `<World of Warcraft>\_forever_\Interface\AddOns\TotemicAccord`.
3. Restart the game (a `/reload` is not enough for a new addon) and log in on a Shaman.
   On other classes it stays silent and does nothing.
4. Type `/ta` to open the options.

To build the zip yourself from a clone, run `.\tools\package.ps1` (see
[Sharing with friends](#sharing-with-friends)).

## The bar

| Button | Left-click / keybind | Right-click |
|---|---|---|
| **Earth, Fire, Water, Air** | cast that element's totem from the active profile (highest rank) | totem chooser (also the small arrow tab) |
| **Action** | cast sequence of your four totems; becomes **Call of the Elements** once learned (level 20) | — |
| **Totemic Recall** | returns your totems to the earth and refunds 25% of their mana | — |
| **Profile** | profile menu: Auto, every profile, "Edit profiles…" | — |

- An element button gets an **outline in the accent colour** while its totem is on the ground.
  In combat Forever hides totem timers from addons, so if a totem expires mid-fight the outline
  can stay lit until combat ends.
- The keybind shows top-right in short form (`asQ` = Alt-Shift-Q). In sequence mode, the Action
  button shows the next step bottom-left (`2/4`).
- The Profile button shows a short code of the active profile. Its dot is green while profiles
  switch automatically and amber while you have pinned one by hand.
- Drag the bar while it's unlocked (`/ta unlock`), then `/ta lock`.

## Profiles

A profile is four totems (one per element) plus a cast-sequence order. Each profile belongs to
a **row** (Global, or one of your saved talent loadouts) and a **situation**: Default, Open
world, Dungeon, Raid, Battleground or Arena.

When you change zone or loadout, the addon picks the first profile that exists in this order:

`loadout:situation` → `loadout:default` → `global:situation` → `global` → your captured native totem bar

- Create profiles in `/ta` → **Profiles**: pick a row and a situation, then **Create**. It
  copies the totems the bar shows right now, and you edit them below.
- The totem chooser on an element button changes the **active** profile.
- Pick a profile from the Profile button to pin it. **Auto** goes back to automatic switching.
- A switch that comes due in combat waits until combat ends (secure buttons can't change in
  combat). A short on-screen message says what switched; you can turn that off.

## Keybinds

`/ta` → **Appearance & keys**: click a box, press a key (Escape clears it). The same bindings
are in the game's Key Bindings menu under *Totemic Accord*. **Apply suggested keybinds**
binds Alt-Shift-Q / E / R / F / G (it tells you first what each key was bound to). **Clear all
keybinds** unbinds every Totemic Accord key.

## Sharing setups

`/ta` → **Import / Export** gives a `TA1:` string with your profiles, sequences and appearance
settings. A friend pastes it into Import. Loadout profiles are matched to their loadouts **by
name**, so give your loadouts the same names (e.g. "Enh", "Resto").

## Appearance

Four themes (Emerald, Tokyo Night, Catppuccin Mocha, Blizzard classic), initials or Blizzard
icons on the buttons, horizontal / vertical / 2×2 grid layouts, scale, button spacing, bar
background opacity, and vivid initials. Everything applies instantly.

**Hide the default totem bar** (same tab) hides the game's own totem bar. Call of the Elements
still drops your totems; ticked in combat, it takes effect when combat ends.

## Slash commands

`/ta` opens the options and `/ta help` lists every command. The most useful ones:

| Command | Does |
|---|---|
| `/ta lock` / `/ta unlock` | lock the bar, or unlock it to drag |
| `/ta reset` | move the bar back to the centre |
| `/ta auto` | return to automatic profile switching |
| `/ta profiles` | print the fallback order and which profiles exist |
| `/ta set <element> <code\|none>` | change a totem in the current profile (`/ta set earth SS`) |
| `/ta capture` | save the native totem bar as the last-resort fallback |
| `/ta macro` | create or update the **TA Sequence** game macro |
| `/ta keys` / `/ta keys clear` | apply the suggested keybinds, or unbind them all |
| `/ta minimap` | show or hide the minimap button |
| `/ta selftest` | diagnostics; paste its output when reporting a problem |

The minimap button: left-click opens the options, right-click opens the profile menu, and
Shift-left-click locks or unlocks the bar. The game's addon dropdown on the minimap lists
Totemic Accord too.

---

# Development

## Requirements (development)

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
testing in game, and it is deliberately not part of `tools/check`.

The API surface is not hardcoded anywhere. `check_api.py` extracts it from Blizzard's own
UI source and writes `tools/wow_globals.lua`, which `.luacheckrc` loads — so one source of
truth feeds both the linter and luacheck. That needs the reference clone:

```bash
git clone --depth 1 --branch forever https://github.com/Gethe/wow-ui-source reference/wow-ui-source
```

Both `reference/` and the generated `tools/wow_globals.lua` are gitignored. Re-clone after
a game patch so the allowlist tracks the live API.

## Testing in game

Turn on Lua errors before testing, and run `/ta selftest` for a diagnostics report:

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
