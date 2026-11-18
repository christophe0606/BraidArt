# BraidArt builds and distribution

## App Store Connect releases

From the repository root, run one command for both platforms:

```sh
./Scripts/release-app-store.sh 1.1.0 7
```

Replace the example with your release version and a higher build number for
each new upload. When you omit the numbers, both builds use the version and
build from `Resources/Info.plist`. The command prints a new folder under
`dist/app-store/` with two files to drop into
[Apple Transporter](https://apps.apple.com/app/transporter/id1450874784):

- `BraidArt-iOS-<version>-<build>.ipa` for iPhone and iPad.
- `BraidArt-macOS-<version>-<build>.pkg` for Mac.

Click **Deliver** in Transporter. Once Apple processes the files, select each
build on its platform's version page in App Store Connect. Use the same version
on those pages as in the command. The command only prepares local files.

### Signing setup on the release Mac

1. Sign into **Xcode > Settings > Accounts** with the developer team that owns
   `com.christophefav.BraidArt`. Xcode automatically signs the iOS archive and
   exports it for App Store Connect.
2. In the developer team's **Manage Certificates** window, use **+** to create
   **Apple Distribution** and **Mac Installer Distribution** if they're missing.
   Xcode stores the certificates and private keys in Keychain. Reuse them for
   future releases until they expire.
3. Install a [Mac App Store Connect provisioning profile](https://developer.apple.com/help/account/provisioning-profiles/create-an-app-store-provisioning-profile/)
   for `com.christophefav.BraidArt` and the local **Apple Distribution**
   certificate. TestFlight requires it. Open the downloaded profile in Xcode
   to install it. The script finds the matching profile in Xcode's cache and
   embeds it before signing. Install a new profile when it expires or you
   replace the Apple Distribution certificate.
4. On the first release, macOS may ask for Keychain approval when `codesign`
   or `productbuild` uses a new private key. Approve the prompt to let the
   command continue.

Pass `--ios` or `--mac` before the version and build to prepare just one
platform. The release folder keeps the Xcode archive and logs if you need to
diagnose signing or export. App Store build numbers must increase for macOS
across versions.

## Local App Sandbox build

```sh
./Scripts/build-app.sh --sandboxed
open dist/sandboxed/BraidArt.app
```

This ad hoc signed build uses App Sandbox and grants read/write access to files
and folders selected through the system. It uses the same
`com.christophefav.BraidArt` bundle identifier as the iPhone and iPad app and
registers `.braidart` as `org.braidart.document`. The standard build lives
at `dist/BraidArt.app`.

The App Store release command uses this build and signs and packages a separate
copy. See [Apple’s App Sandbox documentation](https://developer.apple.com/documentation/xcode/configuring-the-macos-app-sandbox).

## Developer ID distribution

### One-time setup

1. Open **Xcode > Settings > Accounts** and sign in with your Apple Account.
2. Select your **paid developer team**, click **Manage Certificates**, then
   **+ > Developer ID Application**. Xcode installs the certificate and its
   private key in your Mac's Keychain. No app project or Archive setup is needed.
3. At [account.apple.com](https://account.apple.com/), open **Sign-In and Security
   > App-Specific Passwords**, generate a password named “BraidArt notarization”,
   and keep it ready for the next prompt.
4. Find your **Team ID** in the membership details at
   [developer.apple.com/account](https://developer.apple.com/account/).
5. From the repository directory, run:

   ```sh
   ./Scripts/release-app.sh --setup
   ```

   Apple's tool prompts for your developer email, the app-specific password
   (not your usual Apple Account password), and Team ID. It saves them in
   Keychain under the profile name `BraidArt-notary`. If its first prompt asks
   for a **Path to App Store Connect API private key**, press **Return** to leave
   it blank and continue with Apple Account authentication.

#### If Xcode rejects certificate creation

An individual enrollment belongs to its Account Holder, even if Xcode displays
an Admin role. If Xcode reports “This operation can only be performed by the
Account Holder”, use the website route:

1. In **Keychain Access > Certificate Assistant**, choose **Request a Certificate
   From a Certificate Authority**. Enter your email and name, leave the CA email
   blank, select **Saved to disk**, and save the `.certSigningRequest` in Downloads.
   Keychain Access keeps the matching private key in your Mac's Keychain.
2. On the developer website, open **Certificates, Identifiers & Profiles >
   Certificates > +**, choose **Developer ID Application**, and upload that request.
3. Download the resulting `.cer` file and double-click it to install it into your
   **login** keychain on the same Mac.

Creating Developer ID certificates requires the Account Holder role. The website
can also report a permissions error; in that case check the selected account/team
and any pending membership agreements before contacting Apple Developer Support.

The certificate and private key stay in Keychain. The release script reads the
signing identity automatically; no account details belong in the script, a
checked-in configuration file, or an environment file. `--setup` only configures
Keychain; it does not build or upload an app. Setup is required on each release
Mac. Regenerate the app-specific password and repeat `--setup` if credentials
are revoked.

### Each release

Update `CFBundleShortVersionString` and `CFBundleVersion` in
`Resources/Info.plist` for the release, then run:

```sh
./Scripts/release-app.sh
```

The script checks your certificate and Keychain authentication before building.
It runs the normal build, copies the app into a new directory under
`dist/releases/`, signs the CBC shared library and app with Developer ID, Hardened Runtime
and secure timestamps, uploads a temporary ZIP to Apple, and waits for acceptance.
It downloads the notarization log, staples and validates the ticket, checks the
app's signatures and macOS distribution policy, and creates the final ZIP.

Use the ZIP printed after **Ready to distribute**. Its name includes the app
version, build number and executable architectures. The submitted ZIP is named
`notarization-upload.zip`; distribute the final ZIP, which includes the stapled
ticket. Logs and submission status remain beside it in the ignored `dist/`
directory. Review `notarization-log.json` for warnings. Download the final ZIP
through a browser on a fresh Mac or macOS account, then check launching, solving,
opening/saving projects and exporting before publishing it.

Failed signing, rejected notarization or failed ticket/policy checks stop the
script before it creates the final ZIP. If the wait is interrupted, the saved
`submission.plist` contains the ID you can inspect with `xcrun notarytool info`
using `--keychain-profile BraidArt-notary`. No files are published automatically.
Generated logs may contain account or submission metadata; keep them out of Git.

If several Developer ID Application certificates are installed, select the
certificate's SHA1 fingerprint from `security find-identity -v -p codesigning`
using `--identity SHA1`. An alternative Keychain profile can be chosen with
`--profile NAME` on both setup and release commands. These options are supplied
at invocation time; the script does not save them in the repository.

The current build targets macOS 14 or later and the architecture of the build
Mac. Notarization does not make an Apple Silicon app into an Intel/universal app.

## Day-to-day development

Nothing extra is required for local development:

```sh
./Scripts/build-app.sh
open dist/BraidArt.app
```

The build script continues to sign the app and CBC shared library **ad hoc** (`codesign
--sign -`). These local signatures need no certificate, account or network access
for signing. They let you run locally built code on your Mac. Opening
`Package.swift` in Xcode for editing/debugging also remains unchanged.

The release script signs a separate copy, so `dist/BraidArt.app` remains the
development build. Run the release script only when preparing a build to share.
Each changed release must be signed and notarized again; do not edit the contents
of an already signed release app. Local development builds are not notarized
distribution artifacts.

## Apple references

- [Manage signing certificates in Xcode](https://help.apple.com/xcode/mac/current/en.lproj/dev154b28f09.html)
- [Generate an app-specific password](https://support.apple.com/en-us/102654)
- [Sign code for distribution](https://developer.apple.com/documentation/xcode/creating-distribution-signed-code-for-the-mac)
- [Notarize and staple from the command line](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)
