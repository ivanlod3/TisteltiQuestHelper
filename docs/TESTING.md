# Testing

Run `python3 scripts/test.py --lua lua5.1` or `--lua lua5.4`.
The default suite checks all TOC-loaded Lua files, status, stable sorting, reversible watch swaps, diagnostics, geometry/search, detached native quest item alignment, mass journal updates without false progress, recycled highlight guards and empty turn-in recovery.

The optional native-engine harness needs four local reference files from the client being tested: `MixinUtil.lua`, `Blizzard_ObjectiveTrackerModule.lua`, `Blizzard_QuestObjectiveTracker.lua`, `Blizzard_ObjectiveTrackerContainer.lua`. These are not bundled.

```sh
python3 scripts/test.py --lua lua5.1 --native-reference /path/to/local/reference
```

The local G8 build passed 9 groups on both Lua 5.1 and 5.4 (18 executions), including this optional native harness. The empty-result regression fails against G7 and passes against G8. Tests cover zero matches at activation, matches disappearing between reads, the last quest being turned in or becoming incomplete, combat deferral, failed restoration, and recovery after reload.

Live checks on Forever 1.60.1 build 71037 verified search X and magnifier, both blur preferences, no placeholder overlap, native tracker alignment/paging, and empty turn-in messages while the tracker remains visible. The public package changes only version/attribution metadata and documentation from G8; its runtime tests are rerun during packaging.

The obsolete auxiliary-row harnesses (`test_v51_layout.lua`, `test_v51_overflow.lua`) have been removed. New regression coverage is in `test_native_geometry.lua` and `test_recent_progress.lua`.

## Pending in-client verification for this branch

The native-only presentation and taint behaviour require a real Forever 1.60.1 session. The historical build-height strategy (32768) has been removed. Static Lua tests do not certify protected-frame safety. On a disposable copy of the addon, use `/tqhdiag start`, change page, fold/unfold zones, search, enter/leave combat, and `/tqhdiag stop` then `/tqhdiag export` **before reload**. Inspect `ItemButton` parent/anchors/rect and `RECENT` reasons; test multiple simultaneously tracked item-objective quests. If unrelated wheel handlers exist, verify a single wheel notch changes only one page step and does not also scroll another control. Do not modify live addon files while playing.

## Performance validation

Use `/qh perf reset`, stand still for 60 seconds, then `/qh perf`. Repeat while moving, collecting one quest item, scrolling, filtering and leaving combat. Compare event counts, native journal reads/cache hits, render attempts, anchor/height/clamp writes, texture writes and Baganator refreshes. Stable native geometry must not cause repeated quest anchor writes. A native rebuild may require reapplying anchors even when quest data are unchanged. Keep /tqhdiag disabled for representative measurements. The shared read cache is event-invalidated with a 350 ms maximum age; the reversible turn-in watch swap deliberately retains fresh reads for safety. The tracker must perform zero container-height, tracker-height and clamp writes.

### Native-only presentation

The beta.4 report showed 29,425 renders and 39,298 height writes in 617 seconds. The artificial expansion and its feedback protection have been removed, not tuned. TrackerZones now uses one native post-layout hook plus explicit UI actions and combat recovery; the viewport module is read-only and has no subscriptions. Other modules retain independent data events. The turn-in filter still explicitly changes watches when selected by the user; scrolling, grouping and searching never do. The wheel only pages blocks already constructed by Blizzard. Missing native rows are not fabricated and cannot be recovered by this presentation-only approach. Optional native-engine harness now checks the native construction limit instead of expecting expansion to 23 rows. Its required client reference files are not bundled.

`/qh perf` opens a selected, copyable text window (Ctrl+C, or Ctrl+A then Ctrl+C); `/qh perf reset` resets counters and the bounded trace. TQHPERF/2 includes origin request/render counts (coalesced origins are inclusive), options, capacity geometry, rates and the first 24/last 64 trace records. It records actual geometry writes, native clamp/resize and render sources without polling. Use the compact perf report rather than `/tqhdiag start` for representative measurements.

### Bounded presentation with wheel disabled
The native viewport is mandatory for all custom layouts, including fold/unfold with trackerScrollBeta=false. Overflow activates a compact previous/next control; the option only controls the mouse wheel. No native height or clamp writes. If a single row cannot fit or the viewport is unreadable, restore Blizzard's original presentation. Regression covers repeated folding and access to all existing rows with the wheel disabled.

### Automatic overflow wheel
The visible area is bounded by the actual native module height. Overflow automatically enables whole-row wheel navigation, even with legacy trackerScrollBeta=false. When content fits, restore prior wheel state. No pager when the wheel is available; previous/next remains a fallback only for protected/occupied wheel targets. No native dimensions, reparenting or watch changes. Regression covers wheel on/off legacy preferences, all rows reachable, and repeated fold/unfold.

### Item button visibility and unit menu safety
For each native row, hide independently parented, non-protected item buttons only if shown; restore only addon-owned hidden state with matching quest ID, button and parent. Child buttons inherit row visibility. Regression covers folding, search, wheel, native re-show, replacement and disabling presentation. Do not extend unit menus during instances, combat or secret/unknown safety checks; commands remain. Real client taint and protected item buttons still require validation.

### Experimental module compaction
Only move the native TOP anchor of a directly following ProfessionsRecipeTracker when the complete quest presentation fits and leaves space. Preserve the original native anchor; restore on overflow, disable, collapse or unsupported layout, outside restricted states. No native allocation or height changes. Professions EndLayout shares the existing visual scheduler; no new events. Does not recover missing native recipe blocks. Real-client tests must verify hit testing and native rebuilds; indirect module chains are left unchanged.
