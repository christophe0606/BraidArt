#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/clang-cache"
swift build -c release --disable-sandbox --scratch-path .build/swift --product BraidCore
BIN="$(swift build -c release --disable-sandbox --scratch-path .build/swift --show-bin-path)"
mkdir -p .build/icon-generation
rsync -a --delete "$BIN/BraidArt_BraidCore.bundle/" .build/icon-generation/BraidArt_BraidCore.bundle/
swiftc -O -parse-as-library -I "$BIN" Tools/generate-icon.swift "$BIN/libBraidCore.a" -o .build/icon-generation/generate-icon
.build/icon-generation/generate-icon
swift Tools/make-icon.swift Resources/AppIcon.png .build/AppIcon.iconset
iconutil -c icns .build/AppIcon.iconset -o Sources/BraidArt/Resources/AppIcon.icns
