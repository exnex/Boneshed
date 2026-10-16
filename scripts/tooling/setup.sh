#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/env.sh"
test "$(uname -m)" = x86_64 || { echo 'This setup targets Linux x86_64.' >&2; exit 1; }
engine_dir="$TOOLS_ROOT/godot-4.7.2"
mkdir -p "$engine_dir"
archive=Godot_v4.7.2-stable_linux.x86_64.zip
release=https://github.com/godotengine/godot/releases/download/4.7.2-stable
expected_sha=9aa00f7a605200940bce3027a567b782f49bd8e940dd06ae9e987bd65aee1b1467edd56ed84fcdcbdd44354bf613bdbb4e5d2913e925850368e150c59ed54c65
if ! test -f "$engine_dir/$archive"; then
    curl -fL --retry 2 --max-time 180 "$release/$archive" -o "$engine_dir/$archive.tmp"
    mv "$engine_dir/$archive.tmp" "$engine_dir/$archive"
fi
curl -fL --retry 2 --max-time 30 "$release/SHA512-SUMS.txt" -o "$engine_dir/SHA512-SUMS.txt"
# Check against both the official release manifest and the reviewed pinned hash.
python3 - "$engine_dir" "$archive" "$expected_sha" <<'PY'
import hashlib, pathlib, sys, zipfile
directory, name, expected = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]
matches = [line.split()[0] for line in (directory/'SHA512-SUMS.txt').read_text().splitlines()
           if line.split()[-1].lstrip('*') == name]
assert matches == [expected], 'Official checksum differs from pinned checksum'
assert hashlib.sha512((directory/name).read_bytes()).hexdigest() == expected, 'Archive checksum mismatch'
with zipfile.ZipFile(directory/name) as archive:
    executable = name.removesuffix('.zip')
    data = archive.read(executable)
    target = directory/executable
    if not target.exists() or hashlib.sha512(target.read_bytes()).digest() != hashlib.sha512(data).digest():
        staging = directory/(executable+'.tmp')
        staging.write_bytes(data)
        staging.chmod(0o755)
        staging.replace(target)
    target.chmod(0o755)
print('Verified official Godot archive (SHA-512).')
PY
check_godot
if ! command -v Xvfb >/dev/null; then
    # No root required. APT verifies the signed repository metadata and package hash.
    # Debian 13 is the supported cloud base; other distros should install Xvfb normally.
    test -f /usr/share/keyrings/debian-archive-keyring.gpg
    apt_dir="$TOOLS_ROOT/apt"
    mkdir -p "$apt_dir/lists/partial" "$apt_dir/cache/archives/partial" "$TOOLS_ROOT/xvfb"
    printf '%s\n' 'deb [signed-by=/usr/share/keyrings/debian-archive-keyring.gpg] https://deb.debian.org/debian trixie main' > "$apt_dir/sources.list"
    apt_options=(-o "Dir::Etc::sourcelist=$apt_dir/sources.list" -o Dir::Etc::sourceparts=- -o Dir::Etc::parts=- -o "Dir::State::lists=$apt_dir/lists" -o "Dir::Cache=$apt_dir/cache" -o Acquire::Retries=0)
    apt-get "${apt_options[@]}" update
    (cd "$TOOLS_ROOT/xvfb" && apt-get "${apt_options[@]}" download xvfb && dpkg-deb -x xvfb_*.deb .)
fi
if ldd "$(command -v Xvfb)" | grep -q 'not found'; then
    echo 'Xvfb shared libraries are missing; install the matching OS Xvfb dependencies.' >&2
    exit 1
fi
timeout 60 "$GODOT_BIN" --headless --path "$REPO_ROOT" --editor --import
echo 'Setup complete. Run bash scripts/tooling/test.sh or bash scripts/tooling/play.sh.'
