# Testing

Run `python3 scripts/test.py --lua lua5.1` or `--lua lua5.4`.
The default suite checks all TOC-loaded Lua files, status, stable sorting, reversible watch swaps, diagnostics, geometry/search and empty turn-in recovery.

The optional native-engine harness needs four local reference files from the client being tested: `MixinUtil.lua`, `Blizzard_ObjectiveTrackerModule.lua`, `Blizzard_QuestObjectiveTracker.lua`, `Blizzard_ObjectiveTrackerContainer.lua`. These are not bundled.

```sh
python3 scripts/test.py --lua lua5.1 --native-reference /path/to/local/reference
```

The local G8 build passed 9 groups on both Lua 5.1 and 5.4 (18 executions), including this optional native harness. The empty-result regression fails against G7 and passes against G8. Tests cover zero matches at activation, matches disappearing between reads, the last quest being turned in or becoming incomplete, combat deferral, failed restoration, and recovery after reload.

Live checks on Forever 1.60.1 build 71037 verified search X and magnifier, both blur preferences, no placeholder overlap, native tracker alignment/paging, and empty turn-in messages while the tracker remains visible. The public package changes only version/attribution metadata and documentation from G8; its runtime tests are rerun during packaging.

Historical `test_v51_layout.lua` and `test_v51_overflow.lua` target an older auxiliary-row implementation and are retained for reference, not included in the current suite.
