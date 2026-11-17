#!/bin/bash
# Copy checked-in third-party notices into a solver resource directory, offline.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
DESTINATION="${1:?Usage: Scripts/package-licenses.sh /absolute/path/to/Solver}"
if [[ "$DESTINATION" != /* ]]; then
    echo "The license destination must be an absolute path." >&2
    exit 1
fi
for PROJECT in CoinUtils Osi Clp Cgl Cbc; do
    for NOTICE in LICENSE LIBRARY-LICENSE AUTHORS ORIGIN.md; do
        test -s "$ROOT/Licenses/$PROJECT/$NOTICE"
    done
done
for PROJECT in CoinUtils Clp Cgl Cbc; do
    test -s "$ROOT/Licenses/$PROJECT/TOP-LEVEL-AUTHORS"
done
for NOTICE in NOTICE Docs/Licensing.md Licenses/README.md Licenses/Bison/GPL-2.0.txt Licenses/Bison/GENERATED-PARSER-NOTICE.txt Licenses/Bison/ORIGIN.md Licenses/Cbc/AMPL-NOTICE.txt Licenses/Clp/AMPL-NOTICE.txt Licenses/CoinUtils/RATIONAL-NOTICE.txt Docs/ThirdParty.md; do
    test -s "$ROOT/$NOTICE"
done
mkdir -p "$DESTINATION/licenses"
rsync -a --delete "$ROOT/Licenses/" "$DESTINATION/licenses/"
cp "$ROOT/Docs/ThirdParty.md" "$DESTINATION/ThirdParty.md"
# Keep repository-relative inventory links valid in the standalone solver notices.
# Remove an app license left by an earlier build; only upstream licenses belong here.
rm -f "$DESTINATION/LICENSE"
cp "$ROOT/NOTICE" "$DESTINATION/NOTICE"
mkdir -p "$DESTINATION/Docs"
cp "$ROOT/Docs/Licensing.md" "$DESTINATION/Docs/Licensing.md"
cp "$ROOT/Docs/CBCIntegration.md" "$DESTINATION/Docs/CBCIntegration.md"
mkdir -p "$DESTINATION/CBC_CHANGES"
rsync -a --delete "$ROOT/CBC_CHANGES/" "$DESTINATION/CBC_CHANGES/"
