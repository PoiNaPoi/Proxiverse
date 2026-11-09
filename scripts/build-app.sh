#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
configuration="${1:-release}"
iconset=".build/Proxiverse.iconset"
mkdir -p "$iconset"
for size in 16 32 128 256 512; do
    sips -s format png -z "$size" "$size" images/Proxiverse-icon.png --out "$iconset/icon_${size}x${size}.png" >/dev/null
    retina_size=$((size * 2))
    sips -s format png -z "$retina_size" "$retina_size" images/Proxiverse-icon.png --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o Sources/Proxiverse/Resources/Proxiverse.icns
if [ ! -x vendor/mitmproxy.app/Contents/MacOS/mitmdump ]; then ./scripts/fetch-engine.sh; fi
./scripts/swift.sh build -c "$configuration"
bin_path="$(./scripts/swift.sh build -c "$configuration" --show-bin-path)"
app="dist/Proxiverse.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources/Engine"
cp "$bin_path/Proxiverse" "$app/Contents/MacOS/Proxiverse"
# SwiftPM resolves its module bundle inside the app Resources directory.
rm -rf "$app/Contents/MacOS/Proxiverse_Proxiverse.bundle"
rm -rf "$app/Contents/Resources/Proxiverse_Proxiverse.bundle"
cp -R "$bin_path/Proxiverse_Proxiverse.bundle" "$app/Contents/Resources/"
rm -rf "$app/Contents/Resources/Engine/mitmproxy.app"
cp -R vendor/mitmproxy.app "$app/Contents/Resources/Engine/"
cp vendor/mitmproxy-LICENSE.txt "$app/Contents/Resources/"
mkdir -p "$app/Contents/Resources/Legal"
cp LICENSE THIRD_PARTY_NOTICES.md docs/PRIVACY.md docs/AUTHORIZED_USE.md "$app/Contents/Resources/Legal/"
cp -R vendor/third-party "$app/Contents/Resources/Legal/"
cp Sources/Proxiverse/Resources/Proxiverse.icns "$app/Contents/Resources/"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Proxiverse</string>
<key>CFBundleIdentifier</key><string>dev.proxiverse.mac</string>
<key>CFBundleName</key><string>Proxiverse</string>
<key>CFBundleDisplayName</key><string>Proxiverse</string>
<key>CFBundleIconFile</key><string>Proxiverse.icns</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.0.3</string>
<key>CFBundleVersion</key><string>3</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSHumanReadableCopyright</key><string>Proxiverse · mitmproxy engine licensed under MIT</string>
</dict></plist>
PLIST
# Development signature only. Keep the vendor's nested signature intact.
codesign --force --sign - "$app/Contents/Resources/Proxiverse_Proxiverse.bundle"
codesign --force --sign - "$app"
codesign --verify --deep --strict "$app"
touch "$app"
printf 'Built %s\n' "$PWD/$app"
