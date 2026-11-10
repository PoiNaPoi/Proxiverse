#!/usr/bin/env python3
"""Record frozen modules and Mach-O dependencies; requires PyInstaller on macOS."""
import hashlib
import json
import subprocess
import tarfile
from pathlib import Path

from PyInstaller.archive.readers import CArchiveReader

root = Path(__file__).resolve().parent.parent
engine = root / "vendor/mitmproxy.app"
binary = engine / "Contents/MacOS/mitmdump"
archive = CArchiveReader(str(binary))
frozen = archive.open_embedded_archive("PYZ.pyz")
native = []
for path in sorted(engine.rglob("*")):
    if path.is_symlink() or not path.is_file():
        continue
    with path.open("rb") as stream:
        magic = stream.read(4)
    if magic not in (b"\xcf\xfa\xed\xfe", b"\xfe\xed\xfa\xcf", b"\xca\xfe\xba\xbe"):
        continue
    result = subprocess.run(["otool", "-L", str(path)], capture_output=True, text=True, check=True)
    native.append({
        "file": path.relative_to(engine).as_posix(),
        "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
        "linked_libraries": [line.strip() for line in result.stdout.splitlines()[1:]],
    })

embedded = []
for path in sorted(engine.rglob("*.tar")):
    with tarfile.open(path) as bundled:
        embedded.append({
            "file": path.relative_to(engine).as_posix(),
            "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
            "members": sorted(member.name for member in bundled.getmembers()),
        })

output = {
    "scope": "Frozen module names, on-disk Mach-O files and embedded TAR members. "
             "Not a complete inventory of statically linked components or a legal clearance.",
    "mitmdump_sha256": hashlib.sha256(binary.read_bytes()).hexdigest(),
    "frozen_modules": sorted(frozen.toc),
    "native_files": native,
    "embedded_archives": embedded,
}
destination = root / "vendor/third-party/ENGINE_INVENTORY.json"
destination.write_text(json.dumps(output, indent=2) + "\n")
print(f"Recorded {len(frozen.toc)} frozen modules, {len(native)} Mach-O files, "
      f"and {len(embedded)} embedded archives")
