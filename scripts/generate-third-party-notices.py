#!/usr/bin/env python3
"""Generate or verify distribution notices from preserved audit evidence."""
import argparse
import hashlib
import json
import tarfile
from pathlib import Path

root = Path(__file__).resolve().parent.parent
base = root / "vendor/third-party"
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--check", action="store_true", help="verify without changing generated files")
args = parser.parse_args()
config = json.loads((root / "docs/license-audit/distribution.json").read_text())
evidence = root / config["evidence_archive"]["file"]
if hashlib.sha256(evidence.read_bytes()).hexdigest() != config["evidence_archive"]["sha256"]:
    raise SystemExit("Audit evidence archive checksum mismatch")

groups = {}
with tarfile.open(evidence) as archive:
    for item in config["notice_inputs"]:
        data = archive.extractfile(item["member"]).read()
        if hashlib.sha256(data).hexdigest() != item["sha256"]:
            raise SystemExit(f"Audit notice checksum mismatch: {item['member']}")
        if item["member"] == "references/MIT.txt":
            # Standard terms are a reference, not an upstream copyright claim.
            data = data[data.index(b"Permission is hereby granted"):]
        key = hashlib.sha256(data).hexdigest()
        group = groups.setdefault(key, {"text": data, "origins": set()})
        group["origins"].add((item["component"], item["member"]))

parts = [b"Proxiverse third-party licenses and notices\n\n"
         b"Proxiverse-owned code is MIT licensed; third-party material retains its own terms.\n"
         b"Original notices inside the unmodified signed engine are also retained.\n"
         b"This document includes known Python/native components and conservatively selected\n"
         b"macOS Rust normal/build dependency candidates. It is not an exact linked-code SBOM.\n"
         b"Other-platform/dev-only Rust lockfile entries remain in repository audit evidence.\n"
         b"Identical texts are printed once with every selected attribution listed.\n"
         b"fax/fax_derive declare MIT in their original package metadata but supply no separate\n"
         b"copyright/license file. Their declarations and standard MIT terms are reproduced;\n"
         b"no copyright ownership or year has been invented.\n"
         b"For covered source and library replacement instructions, see ENGINE_SOURCE.md.\n\n"]
for number, group in enumerate(groups.values(), 1):
    parts.append(f"{'=' * 72}\nNotice {number}\n".encode())
    for component, member in sorted(group["origins"]):
        parts.append(f"Component: {component}\nUpstream evidence: {member}\n".encode())
    parts.extend([b"\n", group["text"], b"\n\n"])
notices = b"".join(parts)
manifest = {
    "schema": 1,
    "engine": config["engine"],
    "selection_method": config["selection_method"],
    "notices": {"file": "THIRD_PARTY_LICENSES.txt", "sha256": hashlib.sha256(notices).hexdigest()},
    "source_archives": config["sources"],
}
outputs = {
    "THIRD_PARTY_LICENSES.txt": notices,
    "DISTRIBUTION_MANIFEST.json": (json.dumps(manifest, indent=2) + "\n").encode(),
}
for name, data in outputs.items():
    path = base / name
    if args.check:
        if not path.exists() or path.read_bytes() != data:
            raise SystemExit(f"Generated notice mismatch: {name}; review then regenerate")
    else:
        path.write_bytes(data)
for item in config["sources"]:
    path = base / item["file"]
    if hashlib.sha256(path.read_bytes()).hexdigest() != item["sha256"]:
        raise SystemExit(f"Source archive checksum mismatch: {item['file']}")
for name, digest in config["supporting_file_hashes"].items():
    if hashlib.sha256((base / name).read_bytes()).hexdigest() != digest:
        raise SystemExit(f"Source manifest checksum mismatch: {name}")
expected = set(outputs) | set(config["supporting_file_hashes"]) | {item["file"] for item in config["sources"]}
actual = {path.relative_to(base).as_posix() for path in base.rglob("*") if path.is_file()}
if actual != expected:
    raise SystemExit("Distribution file inventory differs from reviewed configuration")
print(f"{'Verified' if args.check else 'Generated'} one notice document with {len(groups)} unique texts; "
      f"{len(config['sources'])} source archives retained")
