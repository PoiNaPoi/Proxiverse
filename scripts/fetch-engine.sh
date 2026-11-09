#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
version=12.2.3
checksum=0a09ee3b82569e8985aff8186e4792618b8e5d0c766098db093d09a87d4b013a
archive=".cache/mitmproxy-${version}-macos-arm64.tar.gz"
mkdir -p .cache vendor
if [ ! -f "$archive" ]; then
  curl -fL --retry 2 "https://downloads.mitmproxy.org/${version}/mitmproxy-${version}-macos-arm64.tar.gz" -o "$archive"
fi
printf '%s  %s\n' "$checksum" "$archive" | shasum -a 256 -c -
if [ ! -d vendor/mitmproxy.app ]; then tar -xzf "$archive" -C vendor; fi
codesign --verify --deep --strict vendor/mitmproxy.app
vendor/mitmproxy.app/Contents/MacOS/mitmdump --version
