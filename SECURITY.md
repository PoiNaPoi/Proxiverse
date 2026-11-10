# Security policy

## Supported versions

Reqnivo is early beta. Security fixes target the latest beta release and the
`main` branch. Older releases do not have a separate security maintenance or
backport commitment. Review the [release notes](https://github.com/PoiNaPoi/Reqnivo/releases)
for known limitations before use.

## Reporting a vulnerability

Please report suspected vulnerabilities privately. Do not publish exploit details
or sensitive data in issues, pull requests, discussions, or workflow logs.

1. Open [Security Advisories](https://github.com/PoiNaPoi/Reqnivo/security/advisories)
   and choose **Report a vulnerability**, if available.
2. If that option is unavailable, open an
   [issue](https://github.com/PoiNaPoi/Reqnivo/issues) titled
   **Request for a private security reporting channel**. Include only the request
   for a private contact; wait for a private channel before sharing details.

Private vulnerability reporting must be enabled separately in GitHub repository
settings. This policy does not establish that it is currently enabled. See
[GitHub's reporting instructions](https://docs.github.com/en/code-security/how-tos/report-and-fix-vulnerabilities/report-privately).

In the private report, include:

- The affected Reqnivo version or commit, macOS version, and Mac architecture.
- A description of the issue, its impact, and any required configuration or access.
- Minimal reproduction steps or a proof of concept using synthetic data.
- Expected and actual behavior, with redacted logs or screenshots if needed.
- Whether the issue also reproduces with the bundled mitmproxy engine directly,
  if already known. This is not required to submit a report.

Do not send production captures, credentials, authorization tokens, cookies, CA
private keys, or personal data. Use synthetic fixtures and redact identifying
hosts, URLs, headers, and bodies. If sensitive evidence is essential, agree on a
private transfer method and handling requirements with the maintainer first.

Reports are handled on a best-effort basis; there is no guaranteed response or
resolution deadline. Please coordinate public disclosure with the maintainer to
allow time to assess the report and prepare a fix.

## Scope and safe testing

Reports may concern the native app, local control API, capture and certificate
handling, rule import/export, build and release scripts, or bundled dependencies
as distributed by Reqnivo. A suspected dependency issue is welcome even if its
upstream origin is uncertain.

Test only systems, devices, and data you own or are explicitly authorized to test.
Use an isolated test environment and synthetic traffic. Do not intercept other
people's traffic or modify their proxy settings or certificate trust stores.

Captured data is not automatically redacted or encrypted by Reqnivo. LAN
capture should only be enabled on a trusted test network. See
[Privacy and cleanup](docs/PRIVACY.md) and [Authorized use](docs/AUTHORIZED_USE.md)
for expected behavior and precautions. Ordinary bugs can be reported through
public issues with a synthetic reproduction and no sensitive data.
