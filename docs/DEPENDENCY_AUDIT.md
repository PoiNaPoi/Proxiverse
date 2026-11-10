# Dependency license review

Reviewed 2026-11-10 for the pinned mitmproxy 12.2.3 macOS arm64 distribution.
The redistribution materials have been organized and checked against the reviewed
engine snapshot. This is a technical record, not legal clearance or proof of
all original native build inputs.

## Distribution set

`vendor/third-party/` now contains nine files: one consolidated notice document,
one distribution manifest, two source manifests, and five source archives.
Original notices in the signed vendor engine remain untouched. Audit evidence,
duplicate source/wheel notices, and cross-platform lockfile inventories are not
copied into the app as individual files.

- `THIRD_PARTY_LICENSES.txt`: all selected copyright/license/NOTICE texts. Exact
  duplicate texts are grouped with their attributions; distinct copyright
  notices are retained. Standard MIT terms are identified as a reference where
  upstream provides only an MIT declaration.
- `DISTRIBUTION_MANIFEST.json`: engine identity/tree hash, notice checksum and
  source archive locations/checksums.
- Covered-source materials: ldap3 2.9.1, urwid 3.0.3, certifi 2026.01.04, plus
  mitmproxy 12.2.3 source/lock and the additional mitmproxy-rs 0.12.9 snapshot.
- `ENGINE_SOURCE.md`: existing modification, rebuild and replacement instructions.
  LGPL source access/replacement preparation and MPL data-source availability
  are preserved; combining notice texts does not replace these requirements.

## Evidence and selection

`docs/license-audit/evidence.tar.gz` preserves the previous raw license files,
source URLs, hashes, source/wheel comparison results, frozen-module inventory,
and the complete Rust lockfile notice collection. It also records additional
cryptography/bcrypt crate notices and upstream declarations for fax/fax_derive.
Nothing is discarded merely to reduce the visible file count.

`docs/license-audit/distribution.json` pins that archive by SHA-256 and explicitly
selects the notice inputs. The original vendor bundle was compared with the
checksum-pinned upstream archive: all 258 file/symlink entries matched. Build
verification checks the same complete tree, rather than just the main executable.

Python package selection retains the previously verified notices, including the
12 additional distributions whose 240 overlapping frozen modules matched their
candidate wheels. Some supplemental version evidence is package/module-level;
that is not treated as proof of every native compilation input.

Rust selection uses the locked source manifests for:

- mitmproxy-rs 0.12.9, with `pyo3/extension-module`, and the macOS certificate
  helper source as a conservative candidate;
- cryptography 46.0.4;
- bcrypt 5.0.0.

Cargo/rustc 1.90.0 were obtained from the official Rust release with checksum
verification. `cargo metadata --locked --offline --format-version 1
--filter-platform aarch64-apple-darwin` was run against each source manifest.
Starting from the named package roots, normal/build dependency edges were
traversed and dev-only edges excluded. This selects 310 unique registry package
candidates plus the pinned boringtun Git dependency. Workspace feature
unification and build dependencies can retain conservative extras; this is a
source-derived attribution set, not an exact list of machine code in the binary.
The source URLs, checksums, roots, enabled features and selected packages are
recorded in `distribution.json`.

Four formerly reported missing-text entries (core-error, tun and the two winapi
import-library packages) are outside this selected graph. They are therefore
not reported as demonstrated gaps in the macOS distribution. The remaining
fax/fax_derive packages declare MIT in their checksum-verified original Cargo
metadata, but have no separate license/copyright files or source copyright
headers. Their declarations are reproduced together with standard MIT terms
from the pinned SPDX license-list reference; no author is invented as a
copyright holder and no year is fabricated.

The bundled Python `ssl` module reports OpenSSL 3.6.2, while cryptography's
backend reports OpenSSL 3.5.5. Supplemental notices for both are retained. The
engine's ordinary `--version` output reports the latter, so that output alone
must not be used as the complete native library inventory.

## Boundaries that remain

- Locked source metadata and matching package/wheel evidence do not independently
  prove the original native release feature/build configuration, compiler
  runtime inputs, or the exact static-link closure. This includes the redirector,
  Rust/C extensions, and the original PyInstaller bootloader.
- The macOS helper source is included conservatively; the upstream bundle's
  helper app metadata is not proof that its executable is present or built from
  this exact source configuration.
- License declarations are upstream evidence, not independent author-ownership
  verification. If upstream corrects a declaration or notice, review that change.
- Reassess the precise redistribution terms, source availability and any modified
  library/relinking arrangement before changing the distribution model. Do not
  describe this review as a legal certification or exact binary SBOM.

These are explicit review limits. A failure to scrape a license file from an
unselected platform package is not by itself a legal defect in the macOS app.

## Maintenance and validation

```sh
python3 scripts/generate-third-party-notices.py
python3 scripts/verify-third-party-notices.py
python3 scripts/verify-engine-sources.py
```

The generator is deterministic and uses only pinned local evidence; it does not
fetch changing upstream content. `--check` compares generated outputs without
writing them. The verifier also rejects an altered vendor engine tree. Build
runs verification after fetching the pinned engine, then copies only the reviewed
distribution directory and end-user legal documents into the app. Packaging
checks the extracted ZIP, source archives, notices and code signatures.

Optional Python 3.14/PyInstaller audit tools remain available:

```sh
python scripts/inventory-engine.py
python scripts/compare-engine-modules.py
```

The inventory writes to `.cache/license-review/`; frozen-code comparison reads
its candidate wheel records from the preserved evidence archive and verifies
wheel checksums. Neither command silently changes the reviewed distribution set.
