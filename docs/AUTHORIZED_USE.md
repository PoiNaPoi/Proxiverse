# Authorized use

Proxiverse is a local HTTP/HTTPS debugging tool for development and authorized
testing. Inspect, modify, or interrupt traffic only when you have permission
covering the relevant systems, devices, accounts, data, and testing activities.
Owning a device, installing a CA, or selecting a domain does not by itself grant
permission to inspect third-party communications or production customer data.

Agree on the scope of team testing before capture. Use test accounts and
synthetic data where possible. Follow applicable laws, contracts, employer
policies, and service terms. Do not use this tool for unauthorized interception,
credential theft, surveillance, or disruption of another person's systems.

## Certificates and network access

- Trust the Proxiverse CA only on devices you are authorized to configure.
  Trust allows interception of selected HTTPS domains when traffic is routed
  through this proxy. Remove that trust when testing is finished.
- Keep the CA private key private. Share only the public CA certificate needed
  by a test device. Never include a private key in a repository or support issue.
- New installations listen on localhost and verify upstream server certificates.
  Existing saved settings are retained; review them before capture.
- Enable LAN access only on a trusted test network. The proxy has no per-device
  authentication or allowlist. The authenticated control API remains on localhost.
- Skipping server certificate verification also skips hostname verification and
  weakens protection for decrypted HTTPS traffic. Use it only for controlled
  debugging; prefer a trusted custom upstream CA when available.
- Stop capture and restore device proxy settings after testing. Quitting or
  deleting Proxiverse does not remove trusted CA certificates from your devices.

## Handling captures

Headers and body previews may contain passwords, session cookies, tokens, personal
data, and confidential business information. Do not publish raw captures, mock
files, screenshots, or logs containing such information. See [Privacy](PRIVACY.md)
for local storage and cleanup details.

## Software terms

Proxiverse code is provided under the MIT License (`LICENSE`). Bundled third-party
software retains its own licenses; see `THIRD_PARTY_NOTICES.md`.
In the source repository these files are at the repository root; in the packaged
app they are beside this document in `Contents/Resources/Legal/`.

The software is a beta and is provided without warranty, subject to the license
and applicable law. This guide describes intended use; it does not add a field-of-use
restriction to the MIT License, waive statutory rights, or grant permission to
access someone else's systems or data.
