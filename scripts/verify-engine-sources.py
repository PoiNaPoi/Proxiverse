#!/usr/bin/env python3
"""Verify the source archives supplied for the bundled engine and LGPL libraries."""
import hashlib
import json
from pathlib import Path

root = Path(__file__).resolve().parent.parent
base = root / "vendor/third-party"
records = json.loads((base / "SOURCE_MANIFEST.json").read_text())
sources = []
for name in ("ldap3", "urwid"):
    record = next(item for item in records if item["name"] == name)
    assert record["source_archive_included"], f"Source not included: {name}"
    path = base / f"{name}-{record['version']}" / record["source_url"].rsplit("/", 1)[1]
    sources.append((path, record["source_sha256"]))
engine = base / "mitmproxy-12.2.3"
record = json.loads((engine / "SOURCE.json").read_text())
sources.append((engine / record["archive"], record["source_sha256"]))
for path, expected in sources:
    actual = hashlib.sha256(path.read_bytes()).hexdigest()
    if actual != expected:
        raise SystemExit(f"SHA-256 mismatch: {path.relative_to(root)}")
    print(f"OK {actual}  {path.relative_to(root)}")
