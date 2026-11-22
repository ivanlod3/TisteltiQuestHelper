# TisteltiQuestHelper

Questing tools for **World of Warcraft: Forever 1.60.1**. The addon interface and announcements are currently in **Spanish**.

## Keep your quests organized

Group the native quest tracker into collapsible zones, sort quests, scroll through the list and search by text. The clear button removes the search and closes the field; a setting controls whether searches stay active when focus is lost.

The **?** button temporarily shows quests ready to turn in. If there are no matches, your tracking stays visible. If you turn in the last matching quest, the addon restores the previous tracking selection. Turning the filter off or reloading also restores that selection, excluding quests no longer in your log.

## More questing tools

- Kill/loot objective icons and counters beside enemy nameplates.
- A character targeting macro named **QuestHelper**, updated outside combat from detected quest NPC names.
- Configurable objective/quest party announcements and manual progress sharing.
- Optional quest item markers in bags and Baganator, plus item tooltip information.
- Appearance settings and temporary highlights for new or updated quests.

## Getting started

Install the `TisteltiUtils_QuestHelper` folder in `Interface/AddOns` and enable **TisteltiUtils - QuestHelper**. Use `/qh options` for settings or `/qh apariencia` for appearance controls. Existing settings are retained when updating.

**Baganator is optional.** No external quest database is required. Party objective/quest announcements are on by default and can be disabled. Turn off overlapping announcements or nameplate icons in one addon if you use several that provide the same feature.

## Compatibility

Validated on **Forever 1.60.1 (Interface 16001)**. Other clients and alternative quest trackers are not validated. Tracker changes pause in combat or when data is restricted. The turn-in filter refuses more than 25 matches. The targeting macro respects the client's 255-character limit and requires a player keypress.

## Support and credits

[Source and documentation](https://github.com/ivanlod3/TisteltiQuestHelper) · [Issues](https://github.com/ivanlod3/TisteltiQuestHelper/issues)

MIT licensed. Quest Together (Tim / missilebarrage) is credited for announcement behavior, and Simple Objective Icons (DharanEmpireAddons) for the native quest-tooltip detection approach. Their attribution notices are preserved. Neither addon is required.
