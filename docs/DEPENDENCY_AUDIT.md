# Dependency license review

Reviewed 2026-11-10 against the pinned mitmproxy 12.2.3 macOS arm64 bundle.
Status: additional notices supplied and inventory expanded; **full binary
license compliance remains open**. This is a technical evidence record, not
legal clearance. Do not mark the release-review license checkbox complete.

## Evidence collected

- `vendor/third-party/ENGINE_INVENTORY.json`: 1,351 frozen PYZ module names,
  77 on-disk Mach-O files with SHA-256 and `otool -L` output, and one embedded
  redirector TAR's member list. Symlink duplicates are excluded. Statically
  linked libraries cannot all be identified by `otool`.
- `ADDITIONAL_NOTICE_SOURCES.json`: 12 additional distributions. PyPI artifact
  SHA-256 values were checked before copying verbatim license/NOTICE/AUTHORS
  files. Source and wheel copies are kept distinct. The setuptools notices
  include vendored libraries, and argon2-cffi-bindings includes libargon2.
- Candidate versions came from the supplied upstream `uv.lock` and available
  runtime version attributes. All 240 Python modules present in both the
  candidate wheels and the frozen engine matched instructions, constants,
  names, argument counts, flags, closure variables, and exception tables.
  Filenames and line tables were excluded; compilation used Python 3.14 with
  optimization levels 0–2. Only overlapping modules were compared. A match is
  strong package-version evidence, not a source authorship or native-build audit.
- `mitmproxy_macos` 0.12.9's embedded redirector TAR matches the PyPI wheel
  byte-for-byte. Its MIT license and package declaration were retrieved from
  upstream tag `v0.12.9`, commit `7e7cc99f8b1d71edad1558ab090e95ebd174fec9`.
- `mitmproxy_rs` 0.12.9: the original `.so` and universal wheel are not identical
  files. Selecting arm64 gives identical contents for all 14 file-backed Mach-O
  sections. Load commands, signatures, and linkedit data were not asserted
  identical. The verified source distribution is supplied with its Cargo.lock.
- `RUST_NOTICE_SOURCES.json`: 485 registry entries from that lockfile were
  downloaded and checked against Cargo checksums. Notices were collected for
  477. Where a crate omitted license files, additional texts were retrieved from
  its `.cargo_vcs_info.json` commit, with per-file source URLs and hashes. The
  pinned boringtun Git dependency's license is supplied too. This is a
  conservative superset including other targets, dev dependencies, and tools;
  it is not a declaration that all 485 packages are linked into the app.

## Distribution obligations reviewed

| Material | Current treatment | Remaining boundary |
| --- | --- | --- |
| Proxiverse-owned source | MIT license and owner provenance declaration | Declaration does not independently verify employer/client agreements. |
| mitmproxy and permissive Python packages | Preserve engine notices; supplement missing upstream texts under `vendor/third-party/` | Reconcile the complete frozen module-to-distribution inventory, including vendored code. |
| ldap3 / urwid (LGPL) | Exact-version source archives, license texts, engine source/lock and tested modification/rebuild/replacement recipe already supplied | Rebuild is not proof of all original build inputs or a legal opinion on the distribution arrangement. Keep source and scripts available with each binary release. |
| certifi / publicsuffix2 data (MPL) | certifi source archive and byte-matched CA data; readable public-suffix data and MPL notices retained | Recheck covered source and notices on updates. |
| argon2-cffi-bindings / libargon2 | Binding license plus nested upstream libargon2 license supplied | Native transitive inventory remains separate. |
| Rust code | Versioned source/lock, crate license texts and upstream attribution snapshots supplied | Exact release target/features, static dependency closure and remaining missing texts are not fully established. |
| Python, OpenSSL, PyInstaller, xz, zstd, mpdecimal | Existing supplemental texts retained | Original bootloader version, Rust/C static dependencies and embedded helper build provenance still need reconciliation. |

A Windows-only LGPL package appears in the Rust lockfile; that alone does not
establish that it is shipped in the macOS binary. Conversely, copying an MIT
license at the top level does not satisfy all third-party obligations. Original
license texts, including dual-license choices, exceptions, and attribution
requirements, remain authoritative.

## Open items before claiming a complete audit

1. Obtain an upstream build-specific dependency inventory or reconstruct the
   release target/features for mitmproxy-rs, cryptography, bcrypt, the macOS
   redirector/certificate helper and PyInstaller. Reconcile their static Rust/C
   dependencies; a Python version or dynamic-library list is insufficient.
2. Resolve the eight lockfile entries without collected license texts:
   aya-ebpf-bindings 0.1.2, core-error 0.0.0, fax 0.2.6, fax_derive 0.2.0,
   tun 0.8.5, winapi-i686-pc-windows-gnu 0.4.0,
   winapi-x86_64-pc-windows-gnu 0.4.0, zune-core 0.4.12. Establish whether they
   are in the distributed target/feature closure before treating them as
   distribution obligations. Manifest `notice_gap` fields preserve lookup
   failures; do not substitute invented copyright notices.
3. Verify that every distributed covered component has its required texts,
   corresponding source or source-access arrangement, and modification/relinking
   provisions where applicable. Review the exact release archive, not just main.

## Reproduce checks

```sh
python3 scripts/verify-engine-sources.py
python3 scripts/verify-third-party-notices.py
```

To regenerate the structural inventory, use Python 3.14 with PyInstaller 6.19.0
(available in the existing local engine-rebuild environment), on macOS:

```sh
python scripts/inventory-engine.py
python scripts/compare-engine-modules.py
```

The comparison command downloads checksum-pinned wheels into `.cache/license-audit/`
as needed and compiles their Python source for comparison without executing it.

The pinned source/wheel URLs, archive hashes, module match lists, original
binary hashes, and copied-notice paths are in the manifests. `NOTICE_HASHES.json`
records the reviewed supplemental text/manifest inventory; it is an integrity
snapshot, not an independent provenance certificate. Changing dependencies
requires a new review rather than merely regenerating the hashes.

New app builds verify these notice/asset hashes and copy this report, provenance
record and the complete third-party directory into `Contents/Resources/Legal/`.
`scripts/verify-app-package.sh` checks their extracted ZIP contents.
