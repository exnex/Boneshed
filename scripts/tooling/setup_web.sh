#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/env.sh"
check_godot
engine_dir="$TOOLS_ROOT/godot-4.7.2"
archive=Godot_v4.7.2-stable_export_templates.tpz
release=https://github.com/godotengine/godot/releases/download/4.7.2-stable
expected=ca4d71c4d7b81dfc15d1a98baa07534aa95b03fdda78a0075b06672e1648d2e5f40980c9adc28d23e1b92e732ee7bf3461997aa804af74ec2fcd7a93ccb84079
if ! test -f "$engine_dir/$archive"; then
    curl -fL --retry 2 --max-time 300 "$release/$archive" -o "$engine_dir/$archive.tmp"
    mv "$engine_dir/$archive.tmp" "$engine_dir/$archive"
fi
curl -fL --max-time 30 "$release/SHA512-SUMS.txt" -o "$engine_dir/SHA512-SUMS.txt"
python3 - "$engine_dir/$archive" "$engine_dir/SHA512-SUMS.txt" "$expected" "$XDG_DATA_HOME/godot/export_templates/4.7.2.stable" <<'PY'
import hashlib,pathlib,sys,zipfile
archive,manifest,expected,target=pathlib.Path(sys.argv[1]),pathlib.Path(sys.argv[2]),sys.argv[3],pathlib.Path(sys.argv[4])
hashes=[line.split()[0] for line in manifest.read_text().splitlines() if line.split()[-1].lstrip('*')==archive.name]
assert hashes==[expected], 'Official template manifest differs from pinned checksum'
with archive.open('rb') as f:
    assert hashlib.file_digest(f,'sha512').hexdigest()==expected, 'Template checksum mismatch'
target.mkdir(parents=True,exist_ok=True)
with zipfile.ZipFile(archive) as z:
    assert z.read('templates/version.txt').decode().strip()=='4.7.2.stable'
    for name in ['web_nothreads_release.zip','web_nothreads_debug.zip','version.txt']:
        (target/name).write_bytes(z.read('templates/'+name))
print('Official single-threaded Web templates verified and installed.')
PY
