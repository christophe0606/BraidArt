#!/bin/bash
# Cross-compile the same pinned, licensed COIN-OR sources as the macOS build.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
SDK="${1:-iphoneos}"
ARCH="${2:-arm64}"
case "$SDK" in
    iphoneos) TARGET="$ARCH-apple-ios26.0" ;;
    iphonesimulator) TARGET="$ARCH-apple-ios26.0-simulator" ;;
    *) echo "Usage: $0 [iphoneos|iphonesimulator] [arm64|x86_64]" >&2; exit 1 ;;
esac
SOURCE="$ROOT/.build/coin-sources"
PREFIX="$ROOT/.build/solver-$SDK-$ARCH"
SYSROOT="$(xcrun --sdk "$SDK" --show-sdk-path)"
JOBS="$(sysctl -n hw.logicalcpu 2>/dev/null || echo 4)"
export CC="$(xcrun --find clang)" CXX="$(xcrun --find clang++)"
export CFLAGS="-target $TARGET -isysroot $SYSROOT -O3 -DNDEBUG"
export CXXFLAGS="$CFLAGS -std=c++11"
export LDFLAGS="-target $TARGET -isysroot $SYSROOT"
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig"
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
if [[ ! -d "$SOURCE/Cbc" ]]; then bash Scripts/build-solver.sh; fi
mkdir -p "$PREFIX"
for SPEC in CoinUtils:2.11.12 Osi:0.108.11 Clp:1.17.11 Cgl:0.60.9 Cbc:2.10.13; do
    PROJECT="${SPEC%%:*}"; VERSION="${SPEC#*:}"
    BUILD="$SOURCE/$PROJECT-$SDK-$ARCH-build"
    mkdir -p "$BUILD"
    if [[ ! -f "$PREFIX/share/braidart-$PROJECT-$VERSION.built" ]]; then
        cd "$BUILD"
        "$SOURCE/$PROJECT/configure" --host="$ARCH-apple-darwin" --prefix="$PREFIX" \
            --disable-shared --enable-static --disable-dependency-tracking \
            --without-lapack --without-blas --without-asl --without-glpk --without-bzlib \
            --without-readline --enable-cbc-parallel > configure.log 2>&1
        make -j "$JOBS" > build.log 2>&1
        make install > install.log 2>&1
        mkdir -p "$PREFIX/share"
        touch "$PREFIX/share/braidart-$PROJECT-$VERSION.built"
    fi
    echo "Built $PROJECT $VERSION for $SDK $ARCH"
done
cd "$ROOT"
"$CXX" -target "$TARGET" -isysroot "$SYSROOT" -std=c++17 -O3 -DNDEBUG \
    -I"$PREFIX/include/coin" -c Native/CBCBridge.cpp -o "$PREFIX/CBCBridge.o"
xcrun libtool -static -o "$PREFIX/lib/libBraidCBC.a" "$PREFIX/CBCBridge.o" \
    "$PREFIX/lib/libCbcSolver.a" "$PREFIX/lib/libCbc.a" "$PREFIX/lib/libCgl.a" \
    "$PREFIX/lib/libOsiClp.a" "$PREFIX/lib/libClpSolver.a" "$PREFIX/lib/libClp.a" \
    "$PREFIX/lib/libOsi.a" "$PREFIX/lib/libCoinUtils.a" 2> "$PREFIX/libtool.log"
