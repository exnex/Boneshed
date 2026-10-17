"""Audit the public artifact and create a ready-to-upload ZIP, never a source archive."""
import hashlib
import json
from pathlib import Path
import struct
import sys
import zipfile

root = Path(sys.argv[1])
preset = sys.argv[2]
allowed = {'.nojekyll', 'index.html', 'index.js', 'index.wasm', 'index.pck',
           'index.audio.worklet.js', 'index.audio.position.worklet.js', 'index.png',
           'index.apple-touch-icon.png', 'index.icon.png'}
names = {p.name for p in root.iterdir()}
assert names <= allowed, f'Unexpected public files: {names - allowed}'
assert {'index.html', 'index.js', 'index.wasm', 'index.pck'} <= names
# Read the Godot PCK directory to verify excluded private docs/tooling/QA paths.
with (root / 'index.pck').open('rb') as pack:
    assert pack.read(4) == b'GDPC'
    version, = struct.unpack('<I', pack.read(4))
    assert version in (2, 3, 4), f'Unsupported PCK format {version}'
    assert struct.unpack('<III', pack.read(12)) == (4, 7, 2), 'PCK engine version differs from the pinned version'
    flags, = struct.unpack('<I', pack.read(4))
    pack.read(8)  # file base
    assert flags & 1 == 0, 'Encrypted PCK directory cannot be audited'
    if version >= 3:
        directory, = struct.unpack('<Q', pack.read(8))
        pack.seek(directory)
    else:
        pack.read(64)
    count, = struct.unpack('<I', pack.read(4))
    assert 0 < count < 10000
    paths = []
    for _ in range(count):
        length, = struct.unpack('<I', pack.read(4))
        assert 0 < length < 4096
        path = pack.read(length).rstrip(b'\0').decode()
        paths.append(path)
        pack.read(8 + 8 + 16 + 4)
assert not any('/docs/' in p or '/artifacts/' in p or '/tooling/' in p or '/.git' in p for p in paths)
assert not any('touch_controls' in p for p in paths), 'Artifact contains removed touch adapter'
if preset == 'Web':
    assert not any('/qa/' in p for p in paths), 'Production artifact contains QA code'
manifest = {'engine': '4.7.2.stable.official.ed1daf0bf', 'preset': preset,
            'threads': False, 'pack_paths': paths,
            'files': {p.name: {'bytes': p.stat().st_size, 'sha256': hashlib.sha256(p.read_bytes()).hexdigest()}
                      for p in sorted(root.iterdir())}}
root.with_suffix('.manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
with zipfile.ZipFile(root.with_suffix('.zip'), 'w', zipfile.ZIP_DEFLATED) as archive:
    for p in sorted(root.iterdir()):
        archive.write(p, p.name)
print(f'Audited {len(paths)} packed resources. Upload ZIP: {root.with_suffix(".zip")}')
