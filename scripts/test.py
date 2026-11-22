"""Portable Lua regression suite; no game access or installed-addon writes."""
from pathlib import Path
import argparse
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
ADDON = ROOT / 'TisteltiUtils_QuestHelper'

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--lua', default='lua')
    parser.add_argument('--native-reference', type=Path)
    args = parser.parse_args()
    # Lua 5.1 uses unpack; 5.4 uses table.unpack. Normalize only in the harness.
    command = [args.lua, '-e', 'unpack=unpack or table.unpack; table.unpack=table.unpack or unpack']
    toc = ADDON / 'TisteltiUtils_QuestHelper.toc'
    runtime = [line.strip() for line in toc.read_text().splitlines() if line.strip() and not line.startswith('#')]
    code = ';'.join('assert(loadfile(' + repr(str(ADDON / f)) + '))' for f in runtime)
    subprocess.run(command + ['-e', code], check=True)
    print('PASS syntax: all ' + str(len(runtime)) + ' TOC-loaded modules', flush=True)
    cases = [
        ('test_filter_incomplete.lua', [ADDON]),
        ('test_diagnostics.lua', [ADDON]),
        ('test_empty_filter.lua', [ADDON]),
        ('test_v51_status.lua', [ADDON/'QuestHelper_Status.lua', ADDON/'QuestHelper_TurnInFilter.lua']),
        ('test_v51_sort.lua', [ADDON/'QuestHelper_TrackerSort.lua']),
        ('test_v51_filter_swap.lua', [ADDON/'QuestHelper_Status.lua', ADDON/'QuestHelper_TurnInFilter.lua']),
        ('test_native_geometry.lua', [ADDON]),
    ]
    if args.native_reference:
        for filename in ('MixinUtil.lua','Blizzard_ObjectiveTrackerModule.lua','Blizzard_QuestObjectiveTracker.lua','Blizzard_ObjectiveTrackerContainer.lua'):
            if not (args.native_reference / filename).is_file():
                parser.error('Missing native reference: ' + filename)
        cases.append(('test_native_engine.lua', [ADDON,args.native_reference.resolve()]))
    for name, paths in cases:
        subprocess.run(command + [str(ROOT/'tests'/name), *map(str,paths)], check=True)
        print('PASS ' + name, flush=True)
    print(str(1 + len(cases)) + ' test groups passed')

if __name__ == '__main__':
    try:
        main()
    except (OSError, subprocess.CalledProcessError) as error:
        print(error, file=sys.stderr)
        sys.exit(1)
