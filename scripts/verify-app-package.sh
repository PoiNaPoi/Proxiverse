#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/verify-third-party-notices.py

app="dist/Reqnivo.app"
output="$PWD/dist/ci"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")
archive="Reqnivo-v${version}-macOS-arm64.zip"
temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT

mkdir -p "$output"
ditto -c -k --sequesterRsrc --keepParent "$app" "$output/$archive"
unzip -tq "$output/$archive"
ditto -x -k "$output/$archive" "$temporary"
extracted="$temporary/Reqnivo.app"
codesign --verify --deep --strict "$extracted"
test "$(lipo -archs "$extracted/Contents/MacOS/Reqnivo")" = arm64
test "$(lipo -archs "$extracted/Contents/Resources/Engine/mitmproxy.app/Contents/MacOS/mitmdump")" = arm64
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$extracted/Contents/Info.plist")" = dev.reqnivo.mac
test "$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$extracted/Contents/Info.plist")" = 14.0
for file in LICENSE THIRD_PARTY_NOTICES.md docs/PRIVACY.md docs/AUTHORIZED_USE.md docs/ENGINE_SOURCE.md; do
    cmp "$file" "$extracted/Contents/Resources/Legal/$(basename "$file")"
done
diff -qr vendor/third-party "$extracted/Contents/Resources/Legal/third-party"
test ! -e "$extracted/Contents/Resources/Legal/DEPENDENCY_AUDIT.md"
test ! -e "$extracted/Contents/Resources/Legal/provenance-assets.json"
cmp vendor/mitmproxy-LICENSE.txt "$extracted/Contents/Resources/mitmproxy-LICENSE.txt"
(
    cd "$output"
    shasum -a 256 "$archive" > SHA256SUMS.txt
    shasum -a 256 -c SHA256SUMS.txt
)
printf 'Verified %s\n' "$output/$archive"
