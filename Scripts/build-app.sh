#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
if [[ ! -x .build/solver-native/bin/cbc ]]; then Scripts/build-solver.sh; fi
export CLANG_MODULE_CACHE_PATH="$ROOT/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$ROOT/.build/clang-cache"
swift build -c release --disable-sandbox --scratch-path .build/swift
BIN="$(swift build -c release --disable-sandbox --scratch-path .build/swift --show-bin-path)"
APP="$ROOT/dist/BraidArt.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/Solver/bin" "$APP/Contents/Resources/Solver/licenses"
cp "$BIN/BraidArt" "$APP/Contents/MacOS/BraidArt"
rsync -a --delete "$BIN/BraidArt_BraidCore.bundle/" "$APP/Contents/Resources/BraidArt_BraidCore.bundle/"
rsync -a --delete "$BIN/BraidArt_BraidArt.bundle/" "$APP/Contents/Resources/BraidArt_BraidArt.bundle/"
cp .build/solver-native/bin/cbc "$APP/Contents/Resources/Solver/bin/cbc"
Scripts/package-licenses.sh "$APP/Contents/Resources/Solver"
cp LICENSE NOTICE "$APP/Contents/Resources/"
cp Docs/Licensing.md "$APP/Contents/Resources/"
cp Resources/Info.plist "$APP/Contents/Info.plist"
for language in en fr; do
    mkdir -p "$APP/Contents/Resources/$language.lproj"
    cp "Resources/$language.lproj/InfoPlist.strings" "$APP/Contents/Resources/$language.lproj/"
done
cp Sources/BraidArt/Resources/AppIcon.icns "$APP/Contents/Resources/BraidArtIcon.icns"
rm -f "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP/Contents/Resources/Solver/bin/cbc"
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"
touch "$APP"
# Refresh Finder's project-file association after rebuilding the bundle in place.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP"
echo "Built $APP"
