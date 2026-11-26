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

The native build-height strategy (`32768`) and taint behaviour require a real Forever 1.60.1 session. Static Lua tests do not certify protected-frame safety. On a disposable copy of the addon, use `/tqhdiag start`, change page, fold/unfold zones, search, enter/leave combat, and `/tqhdiag stop` then `/tqhdiag export` **before reload**. Inspect `ItemButton` parent/anchors/rect and `RECENT` reasons; test multiple simultaneously tracked item-objective quests. If unrelated wheel handlers exist, verify a single wheel notch changes only one page step and does not also scroll another control. Do not modify live addon files while playing.

## Performance validation

Use `/qh perf reset`, stand still for 60 seconds, then `/qh perf`. Repeat while moving, collecting one quest item, scrolling, filtering and leaving combat. Compare event counts, native journal reads/cache hits, render attempts, anchor/height/clamp writes, texture writes and Baganator refreshes. Stable native geometry must not cause repeated quest anchor writes. A native rebuild may require reapplying anchors even when quest data are unchanged. Keep /tqhdiag disabled for representative measurements. The shared read cache is event-invalidated with a 350 ms maximum age; the reversible turn-in watch swap deliberately retains fresh reads for safety. The 32768 build height remains experimental, with no in-game performance or taint certification.

### Geometry feedback circuit breaker

The beta.4 in-client report showed 29,425 renders and 39,298 height writes in 617 seconds. Capacity no longer reconfigures on each render, avoids treating its compensated clamp as a native baseline, and suspends itself for the session if more than 16 actual geometry writes occur within 0.5 seconds. Restores owned geometry once and stops its native update queue. While the experimental scroll remains selected, the tracker falls back to native layout; disable the scroll option to use zones/sort/search without expansion. The new regression simulates repeated native resets and verifies that addon writes stop. This is a safety fallback, not proof that the full-capacity scroll strategy works in Forever.
