#!/bin/bash
# Local arm64 engine rebuild. Keeps the distributed vendor app untouched.
set -euo pipefail
cd "$(dirname "$0")/.."
project_root="$PWD"
python3 scripts/verify-engine-sources.py
if [ "$(uname -s)" != Darwin ] || [ "$(uname -m)" != arm64 ]; then
    printf 'This recipe requires Apple Silicon macOS and Xcode Command Line Tools.\n' >&2
    exit 1
fi
xcrun --find clang >/dev/null
work="$project_root/.cache/engine-rebuild"
commit=6c09d56e4c29a92f5ad01b03199977584b8ea14f
source_root="$work/mitmproxy-$commit"
mkdir -p "$work"
export PIP_CACHE_DIR="$work/pip-cache"
if [ ! -d "$source_root" ]; then
    tar -xzf "vendor/third-party/mitmproxy-12.2.3/mitmproxy-$commit.tar.gz" -C "$work"
fi
tools="$work/tools"
if [ ! -x "$tools/bin/uv" ]; then
    python3 -m venv "$tools"
    "$tools/bin/python" -m pip install --disable-pip-version-check 'uv==0.13.7'
fi
export UV_CACHE_DIR="$work/uv-cache"
export UV_PYTHON_INSTALL_DIR="$work/python"
export PYINSTALLER_CONFIG_DIR="$work/pyinstaller-cache"
export UV_PROJECT_ENVIRONMENT="$source_root/.venv"
export VIRTUAL_ENV="$source_root/.venv"
cd "$source_root"
"$tools/bin/uv" sync --frozen --python 3.14.4
# Install the project non-editably, matching upstream's PyInstaller build workflow.
"$tools/bin/uv" pip install --reinstall --no-cache --no-deps .
# Use our checksum-verified LGPL sources; keep these editable so recipients can
# change them and run this script again without their edits being overwritten.
for library in ldap3-2.9.1 urwid-3.0.3; do
    if [ ! -d "$work/$library" ]; then
        tar -xzf "$project_root/vendor/third-party/$library/$library.tar.gz" -C "$work"
    fi
    "$tools/bin/uv" pip install --reinstall --no-cache --no-deps "$work/$library"
done
"$source_root/.venv/bin/python" - "$source_root" "$work" <<'PY'
import difflib
import sys
from pathlib import Path

source, work = map(Path, sys.argv[1:])
original = source / "release/specs/onedir.spec"
text = original.read_text()
local = text.replace("codesign_identity='Developer ID Application'", "codesign_identity=None")
(source / "release/specs/reqnivo-local.spec").write_text(local)
(work / "PACKAGING.patch").write_text("".join(difflib.unified_diff(
    text.splitlines(keepends=True), local.splitlines(keepends=True),
    fromfile="upstream/onedir.spec", tofile="local/reqnivo-local.spec")))
PY
export PATH="$source_root/.venv/bin:$PATH"
cd release/specs
pyinstaller --clean --noconfirm --workpath "$work/build" --distpath "$work/output" reqnivo-local.spec
engine="$work/output/mitmproxy.app"
"$engine/Contents/MacOS/mitmdump" --version
"$engine/Contents/MacOS/mitmdump" --listen-host 127.0.0.1 --listen-port 0 \
    --set "confdir=$work/selftest-ca" -s "$source_root/release/selftest.py"
codesign --verify --deep --strict "$engine"
"$tools/bin/uv" pip freeze > "$work/requirements-built.txt"
printf 'Built local replacement engine: %s\n' "$engine"
