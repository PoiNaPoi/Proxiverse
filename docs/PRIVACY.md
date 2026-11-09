# Privacy and local data

Applies to Proxiverse 0.0.3. This document describes the application code and bundled
capture workflow, not a certification that every dependency has been independently
audited. Use the app only for [authorized testing](AUTHORIZED_USE.md).

## What is captured

- HTTP traffic routed through the proxy can include URLs, query strings, request
  and response headers, status, timing, client addresses, and body previews.
- HTTPS headers, paths, and bodies are captured only for enabled decryption
  domains. Other HTTPS connections appear as connection metadata such as host
  and port. Existing TLS connections keep their earlier decryption behavior until
  they reconnect.
- Captured headers and textual body previews are not automatically redacted.
  Cookies, authorization tokens, credentials, personal data, and other secrets
  can therefore be visible in the app and stored on disk.

## Where information goes

Capture processing and the native control API run on your Mac. Proxiverse does
not implement a developer-operated capture upload, account, analytics, or
crash-reporting service. Proxied traffic still communicates with its destination
servers unless a debugging rule changes it. Opening documentation uses your
browser; building the app downloads the engine from mitmproxy's distribution site.
Your operating system, browser, backup software, and external device tools have
their own behavior and policies.

LAN mode accepts proxy connections from reachable devices on the local network;
it does not upload captures to a Proxiverse cloud service. Only enable it on a
trusted test network. The control API listens on localhost and requires a
per-capture bearer token.

## Storage and retention

The default directory is `~/Library/Application Support/Proxiverse/`.
`PROXIVERSE_DATA_DIR`, when set, selects a different directory.

| Data | Location and lifetime |
| --- | --- |
| Request/response previews and summaries | JSON files in `captures/`; body previews are limited to 256 KiB per message and the preview disk budget is 128 MiB. These limits are not redaction. |
| Captured metadata | Bounded in-memory history, up to 10,000 flows; the app keeps current previews available after Stop. |
| Preview cleanup | Normal app termination deletes the current capture directory. A fresh app capture owner removes previous capture directories. A crash, forced quit, or cleanup failure can leave files behind. |
| Settings, domain choices, filters, rules, mock files, custom upstream CA | Remain in the application data directory until changed or removed. Rules and mock files can themselves contain confidential data. |
| CA certificate and private key | Remain in `ca/` for reuse. Installing the public CA adds trust on the selected device; quitting the app does not revoke it. |
| Engine log and proxy recovery information | Local application data; no fixed automatic expiration is promised. Do not assume logs are free of sensitive information. |

Application data directories use private filesystem permissions. Capture files
are not encrypted by Proxiverse; directory permissions do not protect against
someone with access to your account, administrator privileges, or backups.

## Cleanup and support

1. Stop capture. If Mac proxy recovery is required, restore the proxy using the
   app or macOS Network settings before removing application data.
2. Restore proxy settings on test devices and remove the Proxiverse/mitmproxy CA
   from each device or trust store where you installed it. On macOS use Keychain
   Access to review the certificate; device Settings handles mobile certificates.
3. Quit the app. Remove leftover `captures/` data if necessary. To reset all local
   Proxiverse data, remove its application data directory only after proxy recovery
   and certificate cleanup. Deleting the app alone does not delete that directory.
4. Review backups, exported Map Local files, clipboard contents, and screenshots
   separately. Local cleanup does not erase copies already shared elsewhere.

For support, start with a minimal reproduction using synthetic data and a
redacted error message. Do not attach production captures, private keys, credentials,
or personal data to public issues. Maintainers should request only the minimum
information needed, through a suitable private channel if sensitive data is essential.

People and organizations collecting or sharing captures are responsible for
determining the applicable legal basis, notices, access controls, retention, and
other data-protection obligations for their use. Installing a CA or clicking a
decryption checkbox is not a substitute for those requirements.
