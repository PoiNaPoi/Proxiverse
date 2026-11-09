# Engine source and local replacement

Proxiverse distributes the official mitmproxy 12.2.3 macOS arm64 engine. The
archives below provide an upstream engine source snapshot and source for its
LGPL libraries, together with a tested local rebuild route. Third-party code
retains its own license. See `THIRD_PARTY_NOTICES.md` and the supplied license
texts; the Proxiverse MIT license does not replace them.

## Obtain and verify source

In a source checkout or the companion `Proxiverse-engine-source-12.2.3.zip`,
the archives are at:

- `vendor/third-party/ldap3-2.9.1/ldap3-2.9.1.tar.gz`
- `vendor/third-party/urwid-3.0.3/urwid-3.0.3.tar.gz`
- `vendor/third-party/mitmproxy-12.2.3/mitmproxy-6c09d56e4c29a92f5ad01b03199977584b8ea14f.tar.gz`

`SOURCE_MANIFEST.json` records the LGPL archive URLs and SHA-256 values.
`mitmproxy-12.2.3/SOURCE.json` records the engine source URL, SHA-256, and full
Git commit resolved from upstream tag `v12.2.3`. The original source archives
are unmodified. The engine archive includes upstream packaging scripts, specs,
`uv.lock`, and tests. LGPL library archives include their source and licenses.

From the checkout or extracted companion archive root:

```sh
python3 scripts/verify-engine-sources.py
```

New app builds also copy these archives, manifests, and this guide into
`Proxiverse.app/Contents/Resources/Legal/` (the archives are under
`third-party/`). Distribute the companion source archive and its checksum
alongside the app so recipients also have the helper scripts and directory layout.

For rebuilding from the app's embedded archives, first obtain the companion
source ZIP or a source checkout for the helper scripts and directory layout.
The scripts use paths relative to their own checkout/archive root.

## Build a local engine

Requirements: Apple Silicon macOS, Xcode Command Line Tools, Python 3.12 or later
with `venv`/`pip`, and network access for build tools, a managed Python 3.14.4,
and dependency downloads. No upstream Developer ID or Apple account is needed.

```sh
bash scripts/rebuild-engine.sh
```

The script:

1. Verifies the supplied archives and extracts them into `.cache/engine-rebuild/`.
2. Installs uv 0.13.7 into a private build-tools environment. Its caches and
   managed Python remain inside that working directory.
3. Installs the engine dependencies using the supplied upstream `uv.lock`
   (`uv sync --frozen`), then installs mitmproxy non-editably, as upstream does
   for PyInstaller packaging.
4. Installs ldap3 and urwid from the supplied local source directories. Fresh
   installs are forced so edits to Python files are reflected on the next build.
5. Creates `proxiverse-local.spec` from upstream `onedir.spec`, changing only
   `codesign_identity='Developer ID Application'` to `codesign_identity=None`.
   This requests local ad-hoc signing rather than upstream's Developer ID.
6. Builds the engine, runs upstream's local self-test with an isolated CA
   directory, and verifies its code signature. No system proxy or trust-store
   change is part of this procedure.

Output:

```text
.cache/engine-rebuild/output/mitmproxy.app
.cache/engine-rebuild/PACKAGING.patch
.cache/engine-rebuild/requirements-built.txt
```

The patch records the packaging change. `requirements-built.txt` records the
installed build environment; local file paths in that report are machine-specific.
It is not a portable requirements file or a statement of all libraries in the
original vendor binary.

## Modify LGPL libraries and rebuild

After the first build, edit the extracted source in:

```text
.cache/engine-rebuild/ldap3-2.9.1/
.cache/engine-rebuild/urwid-3.0.3/
```

Run `bash scripts/rebuild-engine.sh` again. Existing extracted source directories
are retained and reinstalled; they are not replaced by the archives. You can also
edit the extracted mitmproxy source. Generated build output may be overwritten.
Keep your patches separately before removing `.cache/engine-rebuild/`.

To restore pristine source, save any wanted edits, remove only the extracted
directory you want to reset, and rerun the script. The original archives remain
available and checksum-verifiable. Distributors of modified versions must retain
notices and meet the applicable source/modification requirements.

## Use the replacement in a separate app copy

Quit the app copy being modified. From the project root, first create a separate
copy of an existing Proxiverse.app (adjust the input path if necessary):

```sh
ditto dist/Proxiverse.app .cache/Proxiverse-local-engine.app
```

Remove the engine from that separate copy, install the rebuilt engine, and sign
the outer app again:

```sh
rm -rf .cache/Proxiverse-local-engine.app/Contents/Resources/Engine/mitmproxy.app
ditto .cache/engine-rebuild/output/mitmproxy.app .cache/Proxiverse-local-engine.app/Contents/Resources/Engine/mitmproxy.app
codesign --force --sign - .cache/Proxiverse-local-engine.app
codesign --verify --deep --strict .cache/Proxiverse-local-engine.app
```

For an isolated manual capture session, launch its executable with a separate
data directory and unused ports:

```sh
PROXIVERSE_DATA_DIR="$PWD/.cache/local-engine-data" \
PROXIVERSE_PROXY_PORT=19090 PROXIVERSE_API_PORT=19091 \
  .cache/Proxiverse-local-engine.app/Contents/MacOS/Proxiverse
```

Do not enable Capture Mac Traffic or install/trust the test CA unless you intend
to change those settings. Close the app after testing. The replacement is locally
signed, not notarized; it does not retain the upstream distributor's signature.

## Verification boundary

The recipe rebuilds a usable replacement engine. It does not reproduce the
official binary byte-for-byte, reproduce its Developer ID signature, or prove
every original native/Rust build input. The supplied upstream lock pins the two
LGPL versions to the versions observed in the official binary. Other runtime
components may differ between the lock-based rebuild and the original binary.
Further transitive dependency review remains recorded in `PUBLIC_RELEASE_REVIEW.md`.

Local verification on 2026-11-09 (Apple Silicon): archive checksums, lock-based
engine build, upstream self-test, code-signature verification, and Proxiverse's
selective HTTPS smoke test passed. Temporary markers added to both local LGPL
libraries were observed inside a rebuilt binary, verifying that local source
edits reach the packaged engine. The markers were then removed and the final
engine rebuilt and checked again. A separate Proxiverse.app copy with the rebuilt
engine passed deep/strict signature verification. The replacement app's graphical
capture workflow and a second Mac were not tested.
