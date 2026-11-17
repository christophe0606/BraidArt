#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
Scripts/build-solver.sh
export CLANG_MODULE_CACHE_PATH="$ROOT/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$ROOT/.build/clang-cache"
swift build -c release --disable-sandbox --scratch-path .build/swift
BIN="$(swift build -c release --disable-sandbox --scratch-path .build/swift --show-bin-path)"
APP="$ROOT/dist/BraidArt.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Frameworks" "$APP/Contents/Resources/Solver/licenses"
cp "$BIN/BraidArt" "$APP/Contents/MacOS/BraidArt"
# Swift build engines can propagate dependency debug rpaths into release links.
# A distributed executable must search only its bundle and system locations.
while IFS= read -r rpath; do
    case "$rpath" in
        "$ROOT"/.build/*|*/Contents/Developer/Toolchains/*)
            /usr/bin/install_name_tool -delete_rpath "$rpath" "$APP/Contents/MacOS/BraidArt"
            ;;
    esac
done < <(/usr/bin/otool -l "$APP/Contents/MacOS/BraidArt" | awk '
    $1 == "cmd" && $2 == "LC_RPATH" {
        getline; getline
        sub(/^[[:space:]]*path /, ""); sub(/ \(offset.*$/, ""); print
    }')
rsync -a --delete "$BIN/BraidArt_BraidCore.bundle/" "$APP/Contents/Resources/BraidArt_BraidCore.bundle/"
rsync -a --delete "$BIN/BraidArt_BraidArt.bundle/" "$APP/Contents/Resources/BraidArt_BraidArt.bundle/"
cp .build/solver-native/lib/libBraidCBC.dylib "$APP/Contents/Frameworks/"
# Remove the CLI from bundles created by the earlier subprocess implementation.
rm -f "$APP/Contents/Resources/Solver/bin/cbc"
Scripts/package-licenses.sh "$APP/Contents/Resources/Solver"
# Do not retain the former application-license files when rebuilding in place.
rm -f "$APP/Contents/Resources/LICENSE" "$APP/Contents/Resources/Licensing.md"
cp NOTICE "$APP/Contents/Resources/"
cp Resources/Info.plist "$APP/Contents/Info.plist"
for language in en fr; do
    mkdir -p "$APP/Contents/Resources/$language.lproj"
    cp "Resources/$language.lproj/InfoPlist.strings" "$APP/Contents/Resources/$language.lproj/"
done
cp Sources/BraidArt/Resources/AppIcon.icns "$APP/Contents/Resources/BraidArtIcon.icns"
rm -f "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP/Contents/Frameworks/libBraidCBC.dylib"
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"
touch "$APP"
# Refresh Finder's project-file association after rebuilding the bundle in place.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP"
echo "Built $APP"
