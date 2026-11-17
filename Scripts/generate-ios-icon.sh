#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/clang-cache"
bash Scripts/build-solver.sh
swift build --disable-sandbox --scratch-path .build/swift --product BraidCore
BIN="$(swift build --disable-sandbox --scratch-path .build/swift --show-bin-path)"
mkdir -p .build/icon-generation
swiftc -I "$BIN" -I Sources/CBCLibrary -L .build/solver-native/lib -lBraidCBC \
    -Xlinker -rpath -Xlinker "$PWD/.build/solver-native/lib" \
    Tools/make-ios-icon.swift "$BIN/libBraidCore.a" -o .build/icon-generation/make-ios-icon
.build/icon-generation/make-ios-icon
