# TisteltiQuestHelper

Questing tools for **World of Warcraft: Forever 1.60.1** (Interface **16001**).
The current interface and announcement text are in **Spanish**. Other game clients are not validated.

[Download the installable ZIP](https://github.com/ivanlod3/TisteltiQuestHelper/releases/latest) · [Report an issue](https://github.com/ivanlod3/TisteltiQuestHelper/issues) · [Español](docs/LEEME.md)

## Features

- Native quest tracker with collapsible zone headings, stable sorting and mouse-wheel paging.
- Search with a clear/close button and an option to keep the filter when focus is lost.
- Reversible ready-to-turn-in filter. An empty result preserves your tracking; turning in the last matching quest restores the previous selection.
- Kill/loot objective icons and progress counters beside nameplates.
- A character macro named `QuestHelper`, updated with detected quest NPC names outside combat.
- Configurable party announcements and manual progress sharing.
- Optional quest item markers for bags, Baganator integration and item tooltips.
- Appearance controls and temporary highlights for new or updated quests.

## Install

1. Download `TisteltiQuestHelper-0.7.52.zip` from **Releases**, not GitHub's automatic source archive.
2. Extract it into your Forever client's `Interface/AddOns` directory.
3. Check that `Interface/AddOns/TisteltiUtils_QuestHelper/TisteltiUtils_QuestHelper.toc` exists directly at that path.
4. Enable **TisteltiUtils - QuestHelper**, then reload the UI or restart the game.

The internal folder name and SavedVariables identifiers are unchanged, so existing settings are retained.
Baganator is optional. No external quest database is required.

## Use

- `/qh options` — settings, including **Mantener búsqueda al perder el foco**.
- `/qh apariencia` — appearance controls.
- `/qh update` — refresh detected objectives and the targeting macro.
- `/qh debug` or `/qh trackerdiag` — diagnostic information for a bug report.
- Magnifier — open/close search; **X** clears the filter and closes the field.
- **?** — show ready-to-turn-in quests, or restore the previous tracking selection.

If no quests are ready to turn in, the addon displays a message and keeps your tracker visible.
The turn-in filter temporarily changes tracked quests and restores its saved selection when disabled or after reload. Changes to tracking made while the filter is active are not retained as the original selection.

## Compatibility and limits

Tested interactively on Forever **1.60.1, build 71037**, including tracker alignment, paging, search and an empty turn-in result. Automated tests cover additional failure and recovery paths; they do not replace in-game testing.

Tracker changes pause during combat or when required data is restricted. The turn-in filter refuses more than 25 matching quests. The macro has the client's 255-character limit and requires a player keypress; it does not play for you.

Party objective/quest announcements are enabled by default and can be disabled in settings. If another addon announces the same progress or displays the same nameplate icons, disable one overlapping feature to avoid duplicates. Alternative quest trackers are not validated.

## Development

Requires Python 3 and Lua 5.1 or 5.4:

```sh
python3 scripts/test.py --lua lua5.1
python3 scripts/test.py --lua lua5.4
python3 scripts/package.py
```

The package builder uses an explicit allowlist and verifies the ZIP, TOC entries and licenses. It excludes tests, historical notes, screenshots and development files from the installable addon.

An additional integration harness can use locally supplied game UI reference files: see [testing notes](docs/TESTING.md). Those game files are not distributed in this repository.

## License and credits

MIT for this project's code and original project artwork. The existing Quest Together notice is preserved; Simple Objective Icons is credited for the native quest-tooltip detection approach. See [credits](CREDITS.md). Game-provided artwork and screenshots remain the property of their respective owners.
