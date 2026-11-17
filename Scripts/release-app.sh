#!/bin/bash
# Developer ID distribution using only identities and credentials in Keychain.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
PROFILE="BraidArt-notary"
IDENTITY=""
SETUP=false

usage() {
    cat <<'EOF'
Usage: Scripts/release-app.sh [--setup] [--profile NAME] [--identity SHA1]

  --setup          Store notarization credentials interactively in Keychain.
  --profile NAME   Keychain profile name (default: BraidArt-notary).
  --identity SHA1  Select a Developer ID Application certificate if several exist.
  --help           Show this help.

Without --setup: build, copy, sign, notarize, staple, verify and ZIP BraidArt.
The development app in dist/BraidArt.app keeps its local ad hoc signature.
Release files and logs go into a new directory under dist/releases/.
No passwords, account details or private keys are written to configuration files.

First create a Developer ID Application certificate in Xcode:
Settings > Accounts > your paid team > Manage Certificates > +.
Then run this script with --setup once, and without arguments for each release.
See Docs/Distribution.md for the short setup walkthrough.
EOF
}

fail() { echo "Error: $*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --setup) SETUP=true; shift ;;
        --profile|--identity)
            [[ $# -ge 2 && -n "$2" && "$2" != --* ]] || fail "$1 needs a value."
            case "$1" in
                --profile) PROFILE="$2" ;;
                --identity) IDENTITY="$2" ;;
            esac
            shift 2 ;;
        --help|-h) usage; exit 0 ;;
        *) fail "Unknown option: $1. Use --help." ;;
    esac
done

for tool in xcrun security codesign ditto plutil lipo syspolicy_check; do
    command -v "$tool" >/dev/null || fail "Missing $tool. Install/select Xcode 16 or later."
done
xcrun --find notarytool >/dev/null
xcrun --find stapler >/dev/null

if $SETUP; then
    echo "Apple will prompt for your developer email, app-specific password and Team ID."
    echo "Create the password at account.apple.com > Sign-In and Security > App-Specific Passwords."
    echo "At the optional App Store Connect API private-key path prompt, press Return to leave it blank."
    exec xcrun notarytool store-credentials "$PROFILE"
fi

# security -v returns only valid identities with an available private key.
# Use the certificate fingerprint so duplicate display names are unambiguous.
IDENTITY_LIST="$(security find-identity -v -p codesigning)"
CERTIFICATES=()
while IFS= read -r fingerprint; do
    [[ -z "$fingerprint" ]] || CERTIFICATES+=("$fingerprint")
done < <(printf '%s\n' "$IDENTITY_LIST" | awk '/"Developer ID Application:/ {print $2}')
[[ ${#CERTIFICATES[@]} -gt 0 ]] || fail "No valid Developer ID Application certificate with a private key. In Xcode: Settings > Accounts > your paid team > Manage Certificates > + > Developer ID Application."
if [[ -n "$IDENTITY" ]]; then
    FOUND=false
    for fingerprint in "${CERTIFICATES[@]}"; do
        [[ "$fingerprint" != "$IDENTITY" ]] || FOUND=true
    done
    $FOUND || fail "--identity must be a valid Developer ID Application SHA1 from: security find-identity -v -p codesigning"
else
    [[ ${#CERTIFICATES[@]} -eq 1 ]] || fail "Several Developer ID Application identities exist. Select one with --identity SHA1 (see: security find-identity -v -p codesigning)."
    IDENTITY="${CERTIFICATES[0]}"
fi

# Fail before building if the profile is absent, expired or inaccessible.
if ! xcrun notarytool history --keychain-profile "$PROFILE" --output-format plist >/dev/null; then
    fail "Cannot authenticate with Keychain profile '$PROFILE'. Run Scripts/release-app.sh --setup --profile '$PROFILE', or check your network connection."
fi

./Scripts/build-app.sh
DEV_APP="$ROOT/dist/BraidArt.app"
VERSION="$(plutil -extract CFBundleShortVersionString raw -o - "$DEV_APP/Contents/Info.plist")"
BUILD="$(plutil -extract CFBundleVersion raw -o - "$DEV_APP/Contents/Info.plist")"
ARCHS="$(lipo -archs "$DEV_APP/Contents/MacOS/BraidArt")"
ARCH_LABEL="${ARCHS// /-}"
for component in "$VERSION" "$BUILD" "$ARCH_LABEL"; do
    [[ "$component" =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]*$ ]] || fail "Invalid version, build or architecture for the release filename."
done
NAME="BraidArt-$VERSION-$BUILD-$ARCH_LABEL"
mkdir -p "$ROOT/dist/releases"
RELEASE_DIR="$(mktemp -d "$ROOT/dist/releases/$NAME.XXXXXX")"
APP="$RELEASE_DIR/BraidArt.app"
trap 'echo "Release stopped. Files and logs are in: $RELEASE_DIR. A ZIP is ready only after the final Ready to distribute message." >&2' ERR
echo "Release files: $RELEASE_DIR"
ditto "$DEV_APP" "$APP"

# Sign inside out. --deep is for verification, never for signing.
codesign --force --timestamp --options runtime --sign "$IDENTITY" \
    "$APP/Contents/Frameworks/libBraidCBC.dylib"
codesign --force --timestamp --options runtime --sign "$IDENTITY" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

UPLOAD="$RELEASE_DIR/notarization-upload.zip"
ditto -c -k --keepParent "$APP" "$UPLOAD"
# Save the submission ID before waiting, so an interruption is diagnosable.
xcrun notarytool submit "$UPLOAD" --keychain-profile "$PROFILE" \
    --output-format plist > "$RELEASE_DIR/submission.plist"
SUBMISSION_ID="$(plutil -extract id raw -o - "$RELEASE_DIR/submission.plist")"
echo "Waiting for Apple. Submission: $SUBMISSION_ID"
WAIT_RESULT=0
xcrun notarytool wait "$SUBMISSION_ID" --keychain-profile "$PROFILE" \
    --output-format plist > "$RELEASE_DIR/status.plist" || WAIT_RESULT=$?
if ! xcrun notarytool log "$SUBMISSION_ID" --keychain-profile "$PROFILE" \
    "$RELEASE_DIR/notarization-log.json"; then
    echo "Could not download the notarization log. Retry with:"
    echo "xcrun notarytool log $SUBMISSION_ID --keychain-profile \"$PROFILE\""
fi
STATUS="$(plutil -extract status raw -o - "$RELEASE_DIR/status.plist" 2>/dev/null || true)"
if [[ $WAIT_RESULT -ne 0 || "$STATUS" != Accepted ]]; then
    fail "Notarization did not finish successfully (status: ${STATUS:-unknown}). See $RELEASE_DIR; no distribution ZIP was created."
fi

xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
syspolicy_check distribution "$APP"
# ZIP only after stapling; a partial archive never has the distribution filename.
ditto -c -k --keepParent "$APP" "$RELEASE_DIR/$NAME.zip.partial"
mv "$RELEASE_DIR/$NAME.zip.partial" "$RELEASE_DIR/$NAME.zip"
echo "Ready to distribute: $RELEASE_DIR/$NAME.zip"
echo "Review notarization-log.json for warnings and test a browser download before publishing."
