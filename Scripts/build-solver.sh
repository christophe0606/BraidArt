#!/bin/bash
# Build pinned COIN-OR sources locally with Apple's clang; no Homebrew runtime required.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
SOURCE="$ROOT/.build/coin-sources"
PREFIX="$ROOT/.build/solver-native"
mkdir -p "$SOURCE" "$PREFIX"
export CC=/usr/bin/clang CXX=/usr/bin/clang++
export MACOSX_DEPLOYMENT_TARGET=14.0
FLAVOR="macos14-clang-static-v1"
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig"
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
if ! command -v pkg-config >/dev/null 2>&1; then
    echo "pkg-config is required (brew install pkgconf)." >&2
    exit 1
fi
JOBS="$(sysctl -n hw.logicalcpu 2>/dev/null || echo 4)"
for SPEC in CoinUtils:2.11.12 Osi:0.108.11 Clp:1.17.11 Cgl:0.60.9 Cbc:2.10.13; do
    PROJECT="${SPEC%%:*}"
    VERSION="${SPEC#*:}"
    ARCHIVE="$SOURCE/$PROJECT-$VERSION.tar.gz"
    if [[ ! -f "$ARCHIVE" ]]; then
        curl --fail --location --retry 2 "https://github.com/coin-or/$PROJECT/archive/refs/tags/releases/$VERSION.tar.gz" -o "$ARCHIVE.part"
        mv "$ARCHIVE.part" "$ARCHIVE"
    fi
    case "$PROJECT" in
        CoinUtils) EXPECTED=eef1785d78639b228ae2de26b334129fe6a7d399c4ac6f8fc5bb9054ba00de64 ;;
        Osi) EXPECTED=1063b6a057e80222e2ede3ef0c73c0c54697e0fee1d913e2bef530310c13a670 ;;
        Clp) EXPECTED=2c078e174dc1a7a308e091b6256fb34b4017897fc140ea707ba207b2913ea46d ;;
        Cgl) EXPECTED=558421ccd6aa91d6922dd1baa04e37aa4c75ba0472118dc11779e5d6a19bfb38 ;;
        Cbc) EXPECTED=62fde44dcf6f3d05c5cd291d7435cdd1b7e8acd3c78ec481dd39fe49cbc40399 ;;
    esac
    echo "$EXPECTED  $ARCHIVE" | shasum -a 256 -c -
    if [[ ! -d "$SOURCE/$PROJECT" ]]; then
        mkdir -p "$SOURCE/$PROJECT"
        tar -xzf "$ARCHIVE" -C "$SOURCE/$PROJECT" --strip-components=1
    fi
    mkdir -p "$SOURCE/$PROJECT-$FLAVOR-build"
    pushd "$SOURCE/$PROJECT-$FLAVOR-build" >/dev/null
    if [[ ! -f "$PREFIX/share/braidart-$PROJECT-$VERSION-$FLAVOR.built" ]]; then
        "$SOURCE/$PROJECT/configure" --prefix="$PREFIX" --disable-shared --enable-static \
            --without-lapack --without-blas --without-asl --without-glpk \
            --enable-cbc-parallel CXXFLAGS='-O3 -DNDEBUG' > configure.log 2>&1
        make -j "$JOBS" > build.log 2>&1
        make install > install.log 2>&1
        mkdir -p "$PREFIX/share"
        touch "$PREFIX/share/braidart-$PROJECT-$VERSION-$FLAVOR.built"
    fi
    popd >/dev/null
    echo "Built $PROJECT $VERSION"
done
# Link the unmodified static COIN-OR libraries behind BraidArt's small C ABI.
# Only this shared library is loaded by the app; the upstream CLI is not shipped.
/usr/bin/clang++ -std=c++17 -O3 -DNDEBUG -dynamiclib -fvisibility=hidden \
    -mmacosx-version-min=14.0 -I"$PREFIX/include/coin" \
    "$ROOT/Native/CBCBridge.cpp" -L"$PREFIX/lib" \
    -lCbcSolver -lCbc -lCgl -lOsiClp -lClpSolver -lClp -lOsi -lCoinUtils -lbz2 -lz -lpthread \
    -Wl,-install_name,@rpath/libBraidCBC.dylib \
    -Wl,-exported_symbol,_braid_cbc_create -Wl,-exported_symbol,_braid_cbc_cancel \
    -Wl,-exported_symbol,_braid_cbc_event_count -Wl,-exported_symbol,_braid_cbc_destroy \
    -Wl,-exported_symbol,_braid_cbc_search_event_count \
    -Wl,-exported_symbol,_braid_cbc_solve \
    -o "$PREFIX/lib/libBraidCBC.dylib"
codesign --force --sign - "$PREFIX/lib/libBraidCBC.dylib"
echo "Built $PREFIX/lib/libBraidCBC.dylib"
