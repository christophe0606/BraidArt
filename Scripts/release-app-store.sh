#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

fail() { printf 'Error: %s\n' "$*" >&2; exit 1; }

usage() {
    echo "Usage: $0 [--ios | --mac] [VERSION BUILD]"
    echo "Without VERSION BUILD, use the version and build in Resources/Info.plist."
}

platform=both
case "${1:-}" in
    --ios) platform=ios; shift ;;
    --mac) platform=mac; shift ;;
    -h|--help) usage; exit 0 ;;
esac

root="$PWD"
mac_plist="$root/Resources/Info.plist"
plist=/usr/libexec/PlistBuddy
case "$#" in
    0)
        version=$("$plist" -c 'Print :CFBundleShortVersionString' "$mac_plist")
        build=$("$plist" -c 'Print :CFBundleVersion' "$mac_plist")
        ;;
    2) version=$1; build=$2 ;;
    *) usage >&2; exit 2 ;;
esac
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "Use a version like 1.1.0."
[[ "$build" =~ ^[1-9][0-9]*$ ]] || fail "Use a positive integer for the build number."

team=$(awk '$1 == "DEVELOPMENT_TEAM:" { print $2; exit }' iOS/project.yml)
[[ "$team" =~ ^[A-Z0-9]{10}$ ]] || fail "No valid development team in iOS/project.yml."

mkdir -p "$root/dist/app-store"
output=$(mktemp -d "$root/dist/app-store/BraidArt-$version-$build.XXXXXX")
echo "Release folder: $output"

build_ios() {
    local archive="$output/BraidArt-iOS.xcarchive"
    local options="$output/iOS-ExportOptions.plist"
    local export="$output/iOS-export"
    local ipa="$output/BraidArt-iOS-$version-$build.ipa"

    cat > "$options" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>app-store-connect</string>
    <key>destination</key>
    <string>export</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>manageAppVersionAndBuildNumber</key>
    <false/>
</dict>
</plist>
PLIST

    echo "Archiving BraidArt for iPhone and iPad…"
    xcodebuild -project iOS/BraidArt-iOS.xcodeproj -scheme BraidArt \
        -configuration Release -destination 'generic/platform=iOS' \
        -derivedDataPath "$root/.build/app-store-ios" -archivePath "$archive" \
        -allowProvisioningUpdates -hideShellScriptEnvironment \
        MARKETING_VERSION="$version" CURRENT_PROJECT_VERSION="$build" \
        archive > "$output/iOS-archive.log" 2>&1 ||
        fail "iOS archive failed. See $output/iOS-archive.log."

    echo "Exporting the App Store-signed iOS build…"
    # Xcode starts Apple's rsync, which resolves its receiver via PATH.
    # A Homebrew rsync receiver can reject Apple's extended-attributes flag.
    PATH="/usr/bin:/bin:/usr/sbin:/sbin:$PATH" \
        xcodebuild -exportArchive -archivePath "$archive" -exportPath "$export" \
        -exportOptionsPlist "$options" -allowProvisioningUpdates \
        > "$output/iOS-export.log" 2>&1 ||
        fail "iOS export failed. See $output/iOS-export.log. You can also open $archive in Xcode."

    [[ -s "$export/BraidArt.ipa" ]] || fail "Xcode did not export BraidArt.ipa."
    mv "$export/BraidArt.ipa" "$ipa"
    echo "Ready for Transporter (iPhone and iPad): $ipa"
}

find_identity() {
    local kind=$1
    local identities=$2
    local field=$3
    local matches
    matches=$(awk -F '"' -v kind="$kind: " -v team="($team)" -v field="$field" '
        $1 ~ /^[[:space:]]*[0-9]+\)/ && index($2, kind) == 1 &&
        substr($2, length($2) - length(team) + 1) == team {
            split($1, columns, " ")
            print (field == "fingerprint" ? columns[2] : $2)
        }
    ' <<< "$identities")
    [[ -n "$matches" ]] || fail "Missing $kind certificate and private key for team $team in Keychain."
    [[ "$matches" != *$'\n'* ]] || fail "Multiple valid $kind identities for team $team in Keychain."
    printf '%s\n' "$matches"
}

find_mac_profile() {
    local app_id=$1
    local app_identity=$2
    local profile metadata expiry fingerprint now
    now=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
    for profile in "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles/"*.provisionprofile \
                   "$HOME/Library/MobileDevice/Provisioning Profiles/"*.provisionprofile; do
        [[ -f "$profile" ]] || continue
        metadata=$(security cms -D -i "$profile" 2>/dev/null) || continue
        [[ $(plutil -extract Platform.0 raw - 2>/dev/null <<< "$metadata") == OSX ]] || continue
        [[ $(plutil -extract 'Entitlements.com\.apple\.application-identifier' raw - 2>/dev/null <<< "$metadata") == "$app_id" ]] || continue
        [[ $(plutil -extract 'Entitlements.com\.apple\.developer\.team-identifier' raw - 2>/dev/null <<< "$metadata") == "$team" ]] || continue
        if plutil -extract ProvisionedDevices xml1 -o /dev/null - 2>/dev/null <<< "$metadata"; then
            continue
        fi
        [[ $(plutil -extract ProvisionsAllDevices raw - 2>/dev/null <<< "$metadata") != true ]] || continue
        expiry=$(plutil -extract ExpirationDate raw - 2>/dev/null <<< "$metadata") || continue
        [[ "$expiry" > "$now" ]] || continue
        fingerprint=$(plutil -extract DeveloperCertificates.0 raw - <<< "$metadata" |
            base64 -D | shasum -a 1 | awk '{print toupper($1)}') || continue
        [[ "$fingerprint" == "$app_identity" ]] || continue
        printf '%s\n' "$profile"
        return
    done
    fail "No valid Mac App Store Connect provisioning profile for $app_id and the selected Apple Distribution identity. See Docs/Distribution.md."
}

build_mac() {
    local identities app_identity installer_identity profile app entitlements
    local bundle_id=com.christophefav.BraidArt
    local package="BraidArt-macOS-$version-$build.pkg"
    identities=$(security find-identity -v)
    app_identity=$(find_identity 'Apple Distribution' "$identities" fingerprint)
    installer_identity=$(find_identity '3rd Party Mac Developer Installer' "$identities" name)
    profile=$(find_mac_profile "$team.$bundle_id" "$app_identity")

    echo "Building the sandboxed Mac app…"
    Scripts/build-app.sh --sandboxed > "$output/macOS-build.log" 2>&1 ||
        fail "Mac build failed. See $output/macOS-build.log."
    mkdir "$output/macOS-build"
    app="$output/macOS-build/BraidArt.app"
    ditto "$root/dist/sandboxed/BraidArt.app" "$app"
    "$plist" -c "Set :CFBundleShortVersionString $version" "$app/Contents/Info.plist"
    "$plist" -c "Set :CFBundleVersion $build" "$app/Contents/Info.plist"
    [[ $("$plist" -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist") == "$bundle_id" ]] ||
        fail "The Mac app's bundle ID must match the iOS app."

    cp "$profile" "$app/Contents/embedded.provisionprofile"
    entitlements="$output/macOS-build/BraidArt.entitlements"
    cp Resources/BraidArt-Sandbox.entitlements "$entitlements"
    "$plist" -c "Add :com.apple.application-identifier string $team.$bundle_id" "$entitlements"
    "$plist" -c "Add :com.apple.developer.team-identifier string $team" "$entitlements"
    codesign --force --sign "$app_identity" "$app/Contents/Frameworks/libBraidCBC.dylib"
    codesign --force --sign "$app_identity" --entitlements "$entitlements" "$app"
    codesign --verify --deep --strict "$app"

    productbuild --component "$app" /Applications --sign "$installer_identity" "$output/macOS-build/$package"
    pkgutil --check-signature "$output/macOS-build/$package"
    mv "$output/macOS-build/$package" "$output/$package"
    echo "Ready for Transporter (Mac): $output/$package"
}

if [[ "$platform" != mac ]]; then
    build_ios
fi
if [[ "$platform" != ios ]]; then
    build_mac
fi
