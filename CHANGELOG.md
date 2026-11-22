# Changelog

## 0.7.52 — 2026-11-22

First public package of the tested local G8 build.

- Preserve tracker visibility when the ready-to-turn-in filter has no matches; restore the saved tracking selection if the last matching quest is turned in or stops being ready.
- Fix search X so it clears the filter and closes the input in one click.
- Fix magnifier reopening after focus loss and respect the keep-search-on-blur preference.
- Preserve the native search placeholder behavior, preventing overlapping text.
- Retain the native tracker geometry/capacity fixes, consistent alignment, zone grouping, stable sorting and paging.
- Add public documentation, MIT license, upstream credits, automated checks and an installable release ZIP.
- Normalize the displayed version in the TOC and diagnostic labels; gameplay logic is the same as local G8.

In-game verification: Forever 1.60.1 build 71037. Automated validation: Lua 5.1 and 5.4. Earlier development notes are preserved under `docs/history` and describe historical versions, including superseded behavior.
