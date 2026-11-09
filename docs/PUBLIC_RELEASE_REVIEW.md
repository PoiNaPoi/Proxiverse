# Public release review

Prepared 2026-11-09. This is a release review record, not legal clearance.

## Implemented in 0.0.3

- MIT license for Proxiverse-owned code, with third-party licenses kept separate.
- Authorized-use and privacy documentation included with the app.
- Permission and sensitive-data explanations in HTTPS and CA setup views.
- Localhost and upstream certificate verification defaults for fresh settings.
  Existing users' saved debug settings remain intact.
- Original engine bundle and notices retained; supplemental Python/OpenSSL texts
  and a third-party inventory included outside the signed vendor bundle.

## Owner checks before public release

- [x] The project owner confirmed on 2026-11-09 that they have the right to
  publicly distribute all project code and images. The project uses MIT with
  attribution to Proxiverse contributors. This records the owner's declaration;
  employment/client agreements were not independently inspected.
- [x] The same owner declaration covers project images, including the PNG/JPEG
  artwork and generated icon. Retain provenance/permission records outside the
  public repository if they contain confidential information.
- [ ] Review the name/logo for trademark conflicts in intended markets. No
  trademark registry search or legal clearance has been performed.
- [ ] Complete the engine's transitive dependency and native-library license
  audit. THIRD_PARTY_NOTICES.md records the verified subset and gaps; preserving
  vendor files alone is not a complete compliance opinion.
- [x] Pattern-scanned reachable local Git history (2 commits, 102 blobs) for
  private-key markers and common AWS/GitHub/Google API key formats. The only
  matches were deliberately invalid private-key markers in two unit test files;
  neither contains a real private key. Evidence: local
  `.cache/public-release-history-review.json` (not included in the release).
- [ ] Complete a broader sensitive-data review, including personal data,
  confidential fixtures, nonstandard credential formats, and any history not
  present in this checkout. A pattern scan cannot prove their absence.
- [ ] If receiving real captures for support, establish an appropriate private
  intake channel, access controls, retention/deletion process, and data-protection
  basis before collecting them. Do not solicit sensitive files in public issues.
- [ ] Review laws and contractual restrictions for countries where distributing
  or marketing the app, including encryption/export rules where applicable.

## Distribution checks

- LGPL source/rebuild preparation: supplied checksum-verified ldap3 2.9.1 and
  urwid 3.0.3 sources plus the upstream mitmproxy 12.2.3 Git source snapshot.
  `docs/ENGINE_SOURCE.md` describes the tested local engine rebuild and replacement.
  Modified-library probes, upstream self-test, selective HTTPS smoke, and
  separate-app signature checks passed on 2026-11-09. This closes the source
  packaging/rebuild preparation step, not the full transitive license audit.
- Local validation passed: release build, 10 focused settings/HTTPS/upstream
  verification tests, selective HTTPS smoke test, and `git diff --check`.
- `dist/Proxiverse-v0.0.3-macOS-arm64.zip` was checked for ZIP integrity, matching
  bundled legal documents/notices, version metadata, and absence of runtime
  capture/CA paths. Extracted app passed `codesign --verify --deep --strict`.
  SHA-256 values for the local release ZIPs are in `dist/SHA256SUMS.txt`.
- Developer ID signing and notarization have not been completed. They require the
  owner's Apple developer identity; ad-hoc signing remains explicit in release notes.
- Verify the final ZIP and checksums, and test download/first launch on another
  Mac. Build/signature checks do not establish cross-machine behavior.
- Do not describe the release as legally certified, fully dependency-audited,
  notarized, or fully UI-tested unless those checks have actually been completed.

## Reference material

- [GitHub: licensing a repository](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/licensing-a-repository)
- [ETDA: Computer Crimes Act, consolidated 2550/2560 text](https://www.etda.or.th/getattachment/e3c8aef2-00ce-4c91-abea-fef02fc7f07c/Computer-Crimes-Act-BE-2550-and-BE-2560.aspx), especially sections 8 and 13.
- [Thai government PDPA information](https://personal.prd.go.th/th/content/category/detail/id/1832/iid/100260)
- [Mozilla MPL 2.0 distribution FAQ](https://www.mozilla.org/en-US/MPL/2.0/FAQ/)
