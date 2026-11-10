# Vendored library versions

Pinned on 2026-11-09. Re-pin deliberately, never by "just grabbing latest".
Licenses are kept next to each library (or as `Ace3-LICENSE.txt` for the Ace3 set).

| Library | Version / pin | Commit / revision | Source |
|---|---|---|---|
| Ace3 (LibStub, CallbackHandler-1.0, AceAddon-3.0, AceEvent-3.0, AceConsole-3.0, AceDB-3.0, AceGUI-3.0, AceConfig-3.0) | `Release-r1403` (2026-08-12) | `d295b12f8b` | https://github.com/WoWUIDev/Ace3 |
| LibSerialize | `v1.2.3` (2026-10-06) | `aa6e50ddda` | https://github.com/rossnichols/LibSerialize |
| LibDeflate | `1.0.2-release` (2020-06-26) | `6831edcaa9` | https://github.com/SafeteeWoW/LibDeflate |
| LibDataBroker-1.1 | default branch (2008-07-31) | `1a63ede024` | https://github.com/tekkub/libdatabroker-1-1 |
| LibDBIcon-1.0 | minor **57**, SVN **r168** | r168 | https://repos.wowace.com/wow/libdbicon-1-0/trunk (official WowAce SVN) |

## Notes on the picks

- **Ace3 from `WoWUIDev/Ace3`** as the prompt specifies. Its own `Ace3.toc` lists interfaces
  `11508 … 120007` and does **not** list `16001`, so Ace3 r1403 has not been tested against
  Forever. Our addon loads the libraries through our own TOC so the list doesn't gate loading,
  but this is exactly what the M1 **VERIFY** ("Ace3 loads on Forever without Lua errors") covers.
- **Only the needed Ace3 modules are vendored.** Dependencies were read out of the source rather
  than assumed: `AceDB-3.0`→AceAddon, `AceEvent-3.0`→CallbackHandler,
  `AceConfig-3.0`→AceConfigRegistry/Cmd/Dialog + AceGUI + AceAddon + CallbackHandler.
  `AceConfigDropdown-3.0` appears in `AceConfig-3.0.lua` only as a commented-out TODO and does
  not exist in r1403, so it is not vendored. AceComm-3.0 is deliberately skipped (phase 2).
- **LibDBIcon-1.0 came from the official WowAce SVN trunk, not GitHub.** The widely-linked GitHub
  mirror `wowace-clone/LibDBIcon-1.0` is stale: minor **43**, last commit 2019. For comparison,
  the actively maintained addons already installed on this Forever client ship minor 55–56
  (TomTom/Musician 55, Questie/RareScanner 56). The SVN trunk is live and serves minor **57**,
  so it is both the official source and the newest. There is no maintained git home for this
  library. Fetched over plain HTTP with a peg revision (`?p=168`) since no svn client is installed;
  re-pin by bumping that revision.
- **LibDataBroker-1.1's 2008 date is correct** — LDB 1.1 is a tiny, long-frozen spec library.

## Fonts (`TotemicAccord/media/fonts/`)

Both are SIL Open Font License, so they can ship with the addon. `OFL.txt` is kept for each.
**Static TTFs only** — WoW's FreeType handles variable fonts poorly, so `Manrope[wght].ttf`
(the variable build) is deliberately not used.

| Font | Faces | Pin | Source |
|---|---|---|---|
| Manrope | Regular, SemiBold, Bold | `468c0dbe38` (2026-09-14) | https://github.com/googlefonts/manrope |
| JetBrains Mono | Regular, Bold | `v2.304` / `cd5227bd1f` (2023-01-14) | https://github.com/JetBrains/JetBrainsMono |

Note: Manrope is at `googlefonts/manrope`; the older `sharanda/manrope` URL is gone (404).

