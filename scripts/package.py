"""Build and verify a deterministic, installable addon ZIP and submission kit."""
from pathlib import Path
import hashlib
import re
import zipfile

ROOT = Path(__file__).resolve().parents[1]
NAME = 'TisteltiUtils_QuestHelper'
ADDON = ROOT / NAME

def build():
    toc_path = ADDON / (NAME + '.toc')
    toc = toc_path.read_text()
    version = re.search(r'^## Version: ([0-9]+\.[0-9]+\.[0-9]+)$',toc,re.M).group(1)
    assert '## Interface: 16001' in toc
    runtime = [line.strip() for line in toc.splitlines() if line.strip() and not line.startswith('#')]
    assert runtime and all(re.fullmatch(r'[A-Za-z0-9_]+\.lua', name) for name in runtime)
    assert set(runtime) == {p.name for p in ADDON.glob('*.lua')}, 'TOC omits a runtime module'
    payload = [NAME + '.toc', *runtime, 'media/ArrowDown.tga', 'media/ArrowRight.tga',
               'LICENSE.txt', 'LICENSE-QuestTogether.txt', 'LICENSE-SimpleObjectiveIcons.txt', 'LEEME.txt']
    assert len(payload) == len(set(payload))
    for name in payload:
        assert (ADDON/name).is_file() and not (ADDON/name).is_symlink(), name
    assert (ADDON/'LICENSE.txt').read_bytes() == (ROOT/'LICENSE').read_bytes()
    assert ('addon=' + version) in (ADDON/'QuestHelper_Diagnostics.lua').read_text()
    assert ('QuestHelper ' + version + ':') in (ADDON/'QuestHelper_NativeCapacity.lua').read_text()
    output = ROOT/'dist'; output.mkdir(exist_ok=True)
    def archive(path, entries):
        with zipfile.ZipFile(path,'w',compression=zipfile.ZIP_DEFLATED,compresslevel=9) as zip_file:
            for name, data in sorted(entries.items()):
                info=zipfile.ZipInfo(name,date_time=(2026,11,22,0,0,0))
                info.compress_type=zipfile.ZIP_DEFLATED;info.external_attr=0o100644 << 16
                zip_file.writestr(info,data)
        with zipfile.ZipFile(path) as zip_file:
            assert zip_file.testzip() is None
            assert set(zip_file.namelist()) == set(entries)
            for name, data in entries.items(): assert zip_file.read(name) == data
        return path
    addon_zip=archive(output/f'TisteltiQuestHelper-{version}.zip',{NAME+'/'+n:(ADDON/n).read_bytes() for n in payload})
    kit_entries={addon_zip.name:addon_zip.read_bytes(),'CHANGELOG.md':(ROOT/'CHANGELOG.md').read_bytes(),
                 'CREDITS.md':(ROOT/'CREDITS.md').read_bytes(),'LICENSE':(ROOT/'LICENSE').read_bytes()}
    for sub in ['docs/curseforge','docs/images']:
        for p in sorted((ROOT/sub).rglob('*')):
            if p.is_file():kit_entries[str(p.relative_to(ROOT))]=p.read_bytes()
    kit=archive(output/f'TisteltiQuestHelper-{version}-curseforge-kit.zip',kit_entries)
    sums=''.join(hashlib.sha256(p.read_bytes()).hexdigest()+'  '+p.name+'\n' for p in [addon_zip,kit])
    (output/'SHA256SUMS.txt').write_text(sums)
    print(f'Verified {addon_zip.name}: {len(payload)} files; one addon folder; TOC and licenses valid.')
    print(f'Verified {kit.name}: submission documents and original icon. Upload the addon ZIP, not this kit.')
    return addon_zip

if __name__ == '__main__': build()
