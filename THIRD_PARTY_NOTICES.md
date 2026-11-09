# Third-party software notices

The Proxiverse MIT license covers Proxiverse-owned code and documentation. It
does not replace licenses for the bundled engine, its dependencies, third-party
data, or third-party artwork. Preserve all applicable copyright/license notices.

## Engine and runtime

The engine is the official **mitmproxy 12.2.3 macOS arm64** distribution, pinned by
SHA-256 in `scripts/fetch-engine.sh`:

`0a09ee3b82569e8985aff8186e4792618b8e5d0c766098db093d09a87d4b013a`

- Project and source: https://github.com/mitmproxy/mitmproxy/tree/v12.2.3
- Binary: https://downloads.mitmproxy.org/12.2.3/mitmproxy-12.2.3-macos-arm64.tar.gz
- License: MIT, copyright (c) 2013 Aldo Cortesi; full text in
  `vendor/mitmproxy-LICENSE.txt` in the repository and
  `Contents/Resources/mitmproxy-LICENSE.txt` in Proxiverse.app.

`scripts/build-app.sh` copies the complete vendor app, retaining its notices
and nested code signature. Do not strip dependency data or license files.

The binary reports Python **3.14.4** and OpenSSL **3.5.5**. Supplemental license
texts are included in `vendor/third-party/` in the repository and
`Contents/Resources/Legal/third-party/` in Proxiverse.app, copied verbatim from:

- Python: https://github.com/python/cpython/blob/v3.14.4/LICENSE
  (`Python-3.14.4-LICENSE.txt`; includes Python license history and notices).
- OpenSSL: https://github.com/openssl/openssl/blob/openssl-3.5.5/LICENSE.txt
  (`OpenSSL-3.5.5-LICENSE.txt`, Apache-2.0).

Supplemental copies are outside the signed vendor app. They do not imply that
all bundled runtime components have the same license as Python or OpenSSL.

## Verified notices retained inside the engine

Paths below are relative to
`Contents/Resources/Engine/mitmproxy.app/Contents/Resources/` in Proxiverse.app
(or `vendor/mitmproxy.app/Contents/Resources/` in a local checkout).
Versions here are read from bundled directory names, not inferred from upstream
dependency ranges. The license text at each path is authoritative.

| Component | Retained license path |
| --- | --- |
| argon2-cffi 25.1.0 | `argon2_cffi-25.1.0.dist-info/licenses/LICENSE` |
| attrs 25.4.0 | `attrs-25.4.0.dist-info/licenses/LICENSE` |
| click 8.3.1 | `click-8.3.1.dist-info/licenses/LICENSE.txt` |
| cryptography 46.0.4 | `cryptography-46.0.4.dist-info/licenses/LICENSE`, `LICENSE.APACHE`, `LICENSE.BSD` |
| Flask 3.1.2 | `flask-3.1.2.dist-info/licenses/LICENSE.txt` |
| h2 4.3.0 | `h2-4.3.0.dist-info/licenses/LICENSE` |
| itsdangerous 2.2.0 | `itsdangerous-2.2.0.dist-info/LICENSE.txt` |
| MarkupSafe 3.0.3 | `markupsafe-3.0.3.dist-info/licenses/LICENSE.txt` |
| service-identity 24.2.0 | `service_identity-24.2.0.dist-info/licenses/LICENSE` |
| Werkzeug 3.1.5 | `werkzeug-3.1.5.dist-info/licenses/LICENSE.txt` |
| importlib_metadata 8.7.1, vendored by setuptools | `setuptools/_vendor/importlib_metadata-8.7.1.dist-info/licenses/LICENSE` |
| Mozilla Public Suffix List, bundled snapshot 2019-12-21T11:10:15 | `publicsuffix2/mpl-2.0.LICENSE` and `publicsuffix2/public_suffix_list.ABOUT` |

The Public Suffix List data is shipped as `publicsuffix2/public_suffix_list.dat`,
with its MPL notice and readable source data retained. Its bundled ABOUT file
identifies Mozilla and others as copyright holders. Upstream information:
https://publicsuffix.org/ and https://publicsuffix.org/list/public_suffix_list.dat.
The upstream live list may differ from the bundled snapshot. MPL terms apply
to the covered files; they do not automatically relicense Proxiverse-owned files.

## Supplemental dependency notices

`vendor/third-party/SOURCE_MANIFEST.json` records source archive URLs, verified
PyPI SHA-256 values, and copied notice paths for 25 additional Python components.
Versions were read by importing modules inside the bundled engine (the cffi
version comes from `_cffi_backend`). License, NOTICE, AUTHORS, and COPYRIGHT files
were copied verbatim from the exact version's source distribution, including
nested notices when present. In the packaged app the manifest and these files
are under `Contents/Resources/Legal/third-party/`.

Components: aioquic 1.2.0, asgiref 3.11.0, bcrypt 5.0.0, Brotli 1.2.0,
certifi 2026.01.04, cffi 2.0.0, charset-normalizer 3.4.4, h11 0.16.0,
hpack 4.1.0, hyperframe 6.1.0, idna 3.11, kaitaistruct 0.11, ldap3 2.9.1,
pyasn1 0.6.2, pyOpenSSL 26.2.0, pyparsing 3.3.1, pyperclip 1.11.0,
pylsqpack 0.3.23, ruamel.yaml 0.19.1, sortedcontainers 2.4.0,
Tornado 6.5.4, urwid 3.0.3, wcwidth 0.5.3, wsproto 1.3.2, zstandard 0.25.0.

The certifi source archive is also supplied beside its license. Its
`certifi/cacert.pem` was byte-compared with the engine's bundled CA data and
matches. This supplies the corresponding covered CA data rather than pointing
only to a changing upstream download.

The native libraries report liblzma 5.8.3, libzstd 1.5.7, and libmpdec 4.0.1.
Supplemental native notice provenance is recorded in `NATIVE_NOTICE_SOURCES.json`.
The included PyInstaller 6.19.0 text is from the version pinned in mitmproxy's
upstream build configuration; the installed bootloader version has not been
independently established. Its text includes the bootloader distribution exception.

## Audit boundary

This is a verified subset, **not an exhaustive SBOM or completed license audit**.
The vendor app also contains compiled Python modules and native libraries whose
complete dependency versions and notices are not exposed by the directory list.
In particular, mitmproxy-rs and native extensions can include Rust/C/C++ transitive
dependencies beyond the package-level notices collected here. The complete
inventory of frozen Python modules, runtime components, and build-specific native
dependencies still needs reconciliation with the upstream build. Neither the
mitmproxy MIT text nor collecting source-package license files alone establishes
compliance for every embedded component.

Before public binary distribution, reconcile the exact upstream build's package
inventory and native dependency licenses, supply missing license/NOTICE texts and
source-access notices or covered source where required, and record the results.
Do not assign guessed versions or infer that all components use MIT.
See `docs/PUBLIC_RELEASE_REVIEW.md` in the source repository for remaining owner
checks. Updating the engine requires repeating this review and updating this file.
