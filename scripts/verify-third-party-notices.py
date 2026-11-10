#!/usr/bin/env python3
"""Check the recorded notice snapshot and project asset hashes without network access."""
import hashlib
import json
from pathlib import Path

root = Path(__file__).resolve().parent.parent
base = root / "vendor/third-party"
snapshot = json.loads((base / "NOTICE_HASHES.json").read_text())
actual_files = {path.relative_to(base).as_posix() for path in base.rglob("*")
                if path.is_file() and not path.name.endswith(".tar.gz")
                and path.name != "NOTICE_HASHES.json"}
if actual_files != {record["file"] for record in snapshot}:
    raise SystemExit("Notice file inventory changed; review and update NOTICE_HASHES.json")
for record in snapshot:
    path = base / record["file"]
    if hashlib.sha256(path.read_bytes()).hexdigest() != record["sha256"]:
        raise SystemExit(f"Notice checksum mismatch: {record['file']}")

additional = json.loads((base / "ADDITIONAL_NOTICE_SOURCES.json").read_text())
rust = json.loads((base / "RUST_NOTICE_SOURCES.json").read_text())
notices = [notice for package in additional for artifact in package["artifacts"]
           for notice in artifact["notice_files"]]
notices += [notice for package in additional for notice in package.get("upstream_notices", [])]
notices += [notice for package in rust["packages"] for notice in package["notice_files"]]
notices += rust["git_dependency_notices"]
for record in notices:
    if hashlib.sha256((base / record["file"]).read_bytes()).hexdigest() != record["sha256"]:
        raise SystemExit(f"Source notice checksum mismatch: {record['file']}")
for package in additional:
    for artifact in package["artifacts"]:
        if artifact["archive_included"]:
            path = base / artifact["archive_file"]
            if hashlib.sha256(path.read_bytes()).hexdigest() != artifact["sha256"]:
                raise SystemExit(f"Source archive checksum mismatch: {artifact['archive_file']}")
for package in json.loads((base / "SOURCE_MANIFEST.json").read_text()):
    if package["source_archive_included"]:
        path = base / f"{package['name']}-{package['version']}" / package["source_url"].rsplit("/", 1)[1]
        if hashlib.sha256(path.read_bytes()).hexdigest() != package["source_sha256"]:
            raise SystemExit(f"Source archive checksum mismatch: {path.relative_to(base)}")

assets = json.loads((root / "docs/provenance-assets.json").read_text())
for record in assets["files"]:
    if hashlib.sha256((root / record["file"]).read_bytes()).hexdigest() != record["sha256"]:
        raise SystemExit(f"Reviewed asset changed: {record['file']}")

print(f"Verified {len(snapshot)} notice/inventory files and {len(assets['files'])} project assets")
gaps = [package for package in rust["packages"] if not package["notice_files"]]
print(f"Rust lockfile superset: {len(rust['packages'])} registry packages; "
      f"{len(gaps)} without collected notice files")
print("Integrity verification does not prove license compliance or build provenance.")
