# Code and artwork provenance

Recorded 2026-11-10. This records evidence and the owner's declaration, not an
independent legal clearance or a trademark/patent search.

## Owner declaration

On 2026-11-10 the project owner expressly confirmed that they have the right to
distribute all project code and images. The question also covered employer, client, and other
third-party work for which permission might be missing. This is an owner
declaration; underlying employment/client agreements were not independently read.

Third-party dependencies retain their own licenses. The declaration does not
assign their copyright to Proxiverse or replace their distribution requirements.

## Repository evidence

| Material | Evidence and boundary |
| --- | --- |
| `Sources/Proxiverse/` and project tests | Project source under MIT. The owner's distribution-rights declaration covers it; this is not proof of independent authorship of every line. |
| `Sources/Proxiverse/MapLocalTransfer.swift` | Parses supported exported Map Local data into Proxiverse rules. Tests use synthetic data and an optional owner-provided export. This does not independently establish how the format was learned. |
| `images/Proxiverse-icon.png` | Canonical icon input used by `scripts/build-app.sh`. AI-generated Reqnivo artwork selected by the owner on 2026-11-10 to replace the previous project artwork. Creation references and prompts are retained in the design conversation outside this repository. |
| `Sources/Proxiverse/Resources/Proxiverse.icns` | Generated icon; `scripts/build-app.sh` regenerates it from the canonical PNG. |
| `Sources/Proxiverse/Resources/install-certificate.dex` | Android certificate helper. Source is `scripts/android/InstallCertificate.java`; build recipe is `scripts/build-certificate-helper.sh`. A byte-identical DEX rebuild was not part of this provenance review. |
| Bundled engine and dependencies | Upstream mitmproxy. See `THIRD_PARTY_NOTICES.md`, `docs/DEPENDENCY_AUDIT.md`, and the versioned source/notice manifests in `vendor/third-party/`. |

`docs/provenance-assets.json` records SHA-256 values of the reviewed artwork and
helper source/binary. Hashes identify these files; they do not establish ownership.
For new contributions, retain original source links, copyright/license notices,
and permission records. Keep confidential contracts and creation records outside
the public repository, and recheck the declaration when replacing artwork or code.

## Remaining verification

- The absence of copied material cannot be proved by searching source alone.
- UI, icon, and logo similarity to other products has not received an independent
  design/IP review. No trademark registry or patent clearance was performed.
- The independent-project statement in the README clarifies affiliation; it does
  not authorize use of protected material or resolve a contractual restriction.
