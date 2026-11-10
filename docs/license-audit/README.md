# License audit evidence

This directory is for maintainers. It is not copied into Reqnivo.app.

- `evidence.tar.gz` preserves original notice texts and provenance manifests,
  including cross-platform candidates from the former broad Rust lockfile scan.
- `distribution.json` pins the evidence archive and selects the inputs used to
  generate the distribution's consolidated notices. It records macOS candidate
  dependency scopes and the reviewed source/archive identities.

Original manifest paths refer to members of the evidence archive, not current
individual files in `vendor/third-party/`. Historical lookup failures and counts
inside that archive are evidence of the earlier collection, not current findings
that those packages are shipped or noncompliant.

Regenerate with `python3 scripts/generate-third-party-notices.py`, then verify
with `python3 scripts/verify-third-party-notices.py`. Review changed dependency
sources/target features before updating this selection; regenerating notices
alone does not perform that review. See `../DEPENDENCY_AUDIT.md` for the limits.
