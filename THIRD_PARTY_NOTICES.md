# Third-party software notices

The MIT license in `LICENSE` covers Proxiverse-owned material only. Bundled
third-party code, data, and artwork retain their own copyright and license terms.

## Where to find the texts

`vendor/third-party/THIRD_PARTY_LICENSES.txt` contains the supplemental license,
copyright, NOTICE, and attribution texts. Identical texts are printed once with
all selected component attributions retained. It includes known Python/native
components and a conservative set of source-derived macOS Rust dependencies.
It does not assert that every listed build dependency is linked into the app.

In Proxiverse.app, find it at:

`Contents/Resources/Legal/third-party/THIRD_PARTY_LICENSES.txt`

The app's **Licenses & Notices…** menu opens the Legal directory. Original notices
inside the signed engine bundle are retained as well. The standalone mitmproxy
MIT text is at `Contents/Resources/mitmproxy-LICENSE.txt`.

## Engine

Proxiverse redistributes the unmodified official **mitmproxy 12.2.3 macOS arm64**
bundle. Its upstream archive SHA-256 is:

`0a09ee3b82569e8985aff8186e4792618b8e5d0c766098db093d09a87d4b013a`

- Source: https://github.com/mitmproxy/mitmproxy/tree/v12.2.3
- Binary: https://downloads.mitmproxy.org/12.2.3/mitmproxy-12.2.3-macos-arm64.tar.gz
- License: MIT; bundled dependencies retain their own licenses.

`DISTRIBUTION_MANIFEST.json` records the reviewed engine identity, notice document
checksum, and supplied source archives. Build verification checks the entire
vendor file/symlink tree against the reviewed upstream snapshot.

## Covered source and replacement

The app includes exact-version source archives for **ldap3 2.9.1** and
**urwid 3.0.3** (LGPL), together with the upstream mitmproxy source/lock and a
modification/rebuild/replacement guide. The certifi source archive includes the
MPL-covered CA data matched to the bundle. Public Suffix List data is retained
in readable form inside the engine alongside its MPL notices. No MPL or LGPL
license is replaced by Proxiverse's MIT license.

See `docs/ENGINE_SOURCE.md` in the repository, or `ENGINE_SOURCE.md` in the app's
Legal directory, for source locations, verification, modification and local
replacement instructions. Keep the corresponding companion source ZIP and
helper scripts available alongside each binary release. The supplied
mitmproxy-rs source archive is additional review material; it is not a claim
that its Cargo.lock exactly identifies every original native build input.

## Review scope

The repository keeps audit evidence separately under `docs/license-audit/`;
it is not copied into the app. Other-platform and dev-only Rust lockfile entries
are not treated as macOS distribution obligations merely because they are in
that lockfile. `fax` and `fax_derive` declare MIT in upstream package metadata
without separate license files; their original declarations and standard MIT
terms are included, without inventing copyright ownership or dates.

See `docs/DEPENDENCY_AUDIT.md` for the source-selection method and remaining
native build-provenance limits. This material is not legal clearance or a
claim that the exact original static-link inventory has been independently
reproduced. Updating the engine or dependencies requires reviewing the selected
materials and regenerating the notices.
