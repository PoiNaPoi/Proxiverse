#!/usr/bin/env python3
"""Verify reviewed distribution notices, sources and the available vendor engine."""
import hashlib
import json
import subprocess
import sys
from pathlib import Path

root = Path(__file__).resolve().parent.parent
subprocess.run([sys.executable, str(root / "scripts/generate-third-party-notices.py"), "--check"], check=True)
manifest = json.loads((root / "vendor/third-party/DISTRIBUTION_MANIFEST.json").read_text())
engine = root / "vendor/mitmproxy.app/Contents/MacOS/mitmdump"
if engine.exists():
    if hashlib.sha256(engine.read_bytes()).hexdigest() != manifest["engine"]["executable_sha256"]:
        raise SystemExit("Vendor engine changed; review its dependencies and notices before packaging")
    digest = hashlib.sha256()
    vendor = engine.parents[2]
    for path in sorted(vendor.rglob("*")):
        if path.is_symlink():
            record = ["symlink", path.relative_to(vendor).as_posix(), str(path.readlink())]
        elif path.is_file():
            record = ["file", path.relative_to(vendor).as_posix(), hashlib.sha256(path.read_bytes()).hexdigest()]
        else:
            continue
        digest.update((json.dumps(record, ensure_ascii=True, separators=(",", ":")) + "\n").encode())
    if digest.hexdigest() != manifest["engine"]["tree_sha256"]:
        raise SystemExit("Vendor bundle changed; review its dependencies and notices before packaging")
print("Distribution integrity verified; source-derived native candidates are not an exact binary SBOM")
