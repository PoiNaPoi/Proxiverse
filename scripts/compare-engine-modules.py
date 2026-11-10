#!/usr/bin/env python3
"""Compare frozen Python code with checksum-verified wheels without executing them."""
import hashlib
import io
import json
import sys
import tarfile
import types
import urllib.request
import zipfile
from pathlib import Path

from PyInstaller.archive.readers import CArchiveReader

if sys.version_info[:2] != (3, 14):
    raise SystemExit("Use Python 3.14 to read the bundled engine's code objects")

root = Path(__file__).resolve().parent.parent
cache = root / ".cache/license-audit"
cache.mkdir(parents=True, exist_ok=True)
archive = CArchiveReader(str(root / "vendor/mitmproxy.app/Contents/MacOS/mitmdump"))
frozen = archive.open_embedded_archive("PYZ.pyz")
with tarfile.open(root / "docs/license-audit/evidence.tar.gz") as evidence:
    packages = json.load(evidence.extractfile("ADDITIONAL_NOTICE_SOURCES.json"))


def normalized(code):
    if isinstance(code, types.CodeType):
        return (code.co_code, tuple(normalized(value) for value in code.co_consts),
                code.co_names, code.co_varnames, code.co_argcount,
                code.co_posonlyargcount, code.co_kwonlyargcount, code.co_flags,
                code.co_freevars, code.co_cellvars, code.co_exceptiontable)
    return code


total = 0
for package in packages:
    artifact = next(item for item in package["artifacts"] if item["url"].endswith(".whl"))
    path = cache / artifact["url"].rsplit("/", 1)[-1]
    if not path.exists():
        with urllib.request.urlopen(artifact["url"], timeout=60) as response:
            data = response.read()
        if hashlib.sha256(data).hexdigest() != artifact["sha256"]:
            raise SystemExit(f"Wheel checksum mismatch: {path.name}")
        path.write_bytes(data)
    data = path.read_bytes()
    if hashlib.sha256(data).hexdigest() != artifact["sha256"]:
        raise SystemExit(f"Wheel checksum mismatch: {path.name}")
    matched = []
    with zipfile.ZipFile(io.BytesIO(data)) as wheel:
        for name in wheel.namelist():
            if not name.endswith(".py"):
                continue
            module = name[:-3].replace("/", ".").removesuffix(".__init__")
            if module not in frozen.toc:
                continue
            original = normalized(frozen.extract(module))
            source = wheel.read(name)
            if not any(normalized(compile(source, name, "exec", optimize=level)) == original
                       for level in (0, 1, 2)):
                raise SystemExit(f"Frozen code differs: {package['name']} / {module}")
            matched.append(module)
    if sorted(matched) != sorted(package["frozen_module_comparison"]["matched"]):
        raise SystemExit(f"Frozen module inventory changed: {package['name']}")
    total += len(matched)
    print(f"{package['name']} {package['candidate_version']}: {len(matched)} modules matched")
print(f"Verified {total} overlapping Python modules; native build provenance remains separate")
