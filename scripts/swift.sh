#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.cache/clang"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.cache/swift-modules"
command_name="${1:-build}"
if [ "$#" -gt 0 ]; then shift; fi
exec swift "$command_name" --disable-sandbox --cache-path "$PWD/.cache/swiftpm" "$@"
