# Distributing BraidArt outside the Mac App Store

## One-time setup

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

### If Xcode rejects certificate creation

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

## Each release

Update `CFBundleShortVersionString` and `CFBundleVersion` in
`Resources/Info.plist` for the release, then run:

```sh
./Scripts/release-app.sh
```

The script checks your certificate and Keychain authentication before building.
It runs the normal build, copies the app into a new directory under
`dist/releases/`, signs the CBC solver and app with Developer ID, Hardened Runtime
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

The build script continues to sign the app and CBC solver **ad hoc** (`codesign
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
