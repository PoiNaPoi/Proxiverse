#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
sdk="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-$HOME/Library/Android/sdk}}"
version="$(ls "$sdk/build-tools" | sort -V | tail -1)"
build_dir="$(mktemp -d "${TMPDIR:-/tmp}/reqnivo-cert-build.XXXXXX")"
trap 'rm -rf "$build_dir"' EXIT
javac --release 8 -d "$build_dir" scripts/android/InstallCertificate.java
"$sdk/build-tools/$version/d8" --min-api 24 --output "$build_dir" "$build_dir/InstallCertificate.class"
cp "$build_dir/classes.dex" Sources/Reqnivo/Resources/install-certificate.dex
