# Totemic Accord

A themed shaman totem bar for **World of Warcraft: Forever** (client 1.60.1, interface
16001), with totem profiles that switch **automatically by talent loadout and situation**.

> Status: **v0.1.0.** Everything is built. Call of the Elements (level 20) is the one part not
> yet checked in game. `docs/decisions.md` logs every design decision, and
> `docs/testing.md` holds the in-game checklists.

Other Forever totem bars exist, but none of them switches totem sets automatically by loadout
and instance type. That, the per-profile cast sequence and the themes are what this one adds.

## Installing (players)

1. Unzip `TotemicAccord-0.1.0.zip` so the folder lands at
   `<World of Warcraft>\_forever_\Interface\AddOns\TotemicAccord`.
2. Restart the game (a `/reload` is not enough for a new addon) and log in on a Shaman.
   On other classes it stays silent and does nothing.
3. Type `/ta` to open the options.

## The bar

| Button | Left-click / keybind | Right-click |
|---|---|---|
| **Earth, Fire, Water, Air** | cast that element's totem from the active profile (highest rank) | totem chooser (also the small arrow tab) |
| **Action** | cast sequence of your four totems; becomes **Call of the Elements** once learned (level 20) | — |
| **Totemic Projection** | pulls your totems to you | — |
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

The interactive visual reference is `docs/mock/totemic-accord-mock.html`; open it in a
browser. `docs/CLAUDE_CODE_PROMPT.md` is the original spec.

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
