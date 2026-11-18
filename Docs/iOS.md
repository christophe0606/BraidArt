# BraidArt for iPhone and iPad

The native iOS app shares BraidCore, the app model, settings, crop editor, video
playback and Metal/SceneKit renderer with the macOS app. It requires iOS/iPadOS 26
or later; the Mac app continues to support macOS 14 (Sonoma) or later.

- iPad: landscape, with a resizable settings sidebar on the left. Drag its handle
  to change its width; the sidebar button in the toolbar hides or restores it.
  Width and visibility are remembered across launches.
- iPhone: portrait and landscape, with Prepare, Tile Library, Result and 3D tabs.
  The toolbar above the workspace has Open, Settings and Save & export.
  Prepare adds Output dimensions, Image width, and Luminance and contrast.
  Tile Library adds Strand geometry, and 3D adds Picture dimensions.
  Live controls open in a bottom panel while
  the toolbar and tab bar are hidden. Drag the panel handle to resize it, scroll
  its controls or the exposed workspace independently, and tap Close to return.
  Settings opens the full-screen Tiles & palette and Partition solve controls.
  Weaving progress appears over the workspace.
  In phone landscape, the 3D controls use one compact row to leave room for the scene.
- 3D: drag with one finger to rotate, two fingers to pan, and pinch to zoom.
  Reset Camera centers the sculpture and restores the front view. Picture
  dimensions sets the framing and size of the PNG captured from this view.
  The red frame uses the Prepare dimensions until you choose a size in 3D.
- Result: pinch to zoom and drag the enlarged picture; Fit resets the view.
  The PNG retains the completed weave's dimensions. Set the next size in Prepare.
- Open pictures and videos from the Photos or Files picker. From another app,
  share a single photo or video and choose BraidArt. Tap Done, then open BraidArt
  to load it in Prepare. Each return to BraidArt imports the next pending share.
- Choose an export format to open the system share sheet. Available actions
  depend on the file type and installed apps. Pictures and videos can be saved
  to Photos, and files can be saved to Files or shared with other apps. Solution
  and tile data is shared as a ZIP archive. The export button is available from
  every iPhone tab and from Result and 3D on iPad. Capturing a 3D view as PNG
  requires the 3D tab.
- Help opens automatically on the first launch on each device. It remains
  accessible from the information button on later launches. It shares the Mac
  illustrated help, with the
  linked Opt Art book reference visible at the top. Third-party license texts,
  copyright notices, image rights and upstream source links remain accessible
  from help.
- The iOS icon uses the same nine braid tiles as the Mac icon, rendered opaque
  and edge to edge so that iOS can apply its own mask without a black border.
  Regenerate it using `Scripts/generate-ios-icon.sh`.

## Background weaving

When the app moves to the background (including screen lock), the current
partition continues. Its validated tile choices and report are committed before
pausing. No next partition, video frame, audio-processing loop or result render
is admitted while paused. Returning to the app resumes automatically; Cancel
also works while the job is waiting. Pause time is excluded from solve timings.

A user-started weave requests
[`BGContinuedProcessingTask`](https://developer.apple.com/documentation/backgroundtasks/bgcontinuedprocessingtask)
CPU runtime. The system displays a Live Activity with the current partition.
CBC's search has an unknown step count, so progress is indeterminate and reports
actual native solver activity, rather than a fabricated completion percentage.
The runtime allowance ends as soon as the current partition reaches its boundary.

If extended runtime is unavailable, the app uses the ordinary UIKit background
grace period. If iOS expires either allowance, only the unfinished native request
is interrupted; its uncommitted choices are discarded and that partition is
retried on activation. Previously committed partitions remain in the same job.
Audio encoding also cooperates with the pause instead of polling while waiting.

A paused job lives in the app's memory and survives ordinary background suspension.
Force-quitting the app or OS termination discards that in-memory job; this is not
a persistent job queue or a promise of unlimited background execution. No audio,
location or other unrelated background capability is used to keep the app alive.

## Build

Install Xcode and `xcodegen` (and `pkg-config` for the bundled solver), then run:

```sh
xcodegen generate --spec iOS/project.yml
xcodebuild -project iOS/BraidArt-iOS.xcodeproj -scheme BraidArt \
  -destination 'generic/platform=iOS' -derivedDataPath .build/ios \
  -allowProvisioningUpdates build
```

The checked-in Xcode project can also be opened directly. The app and Share
Extension use `group.com.christophefav.BraidArt` for the local import handoff.
When signing with another development team, use an App Group registered to that
team in `BraidArt.entitlements` and `SharedMediaInbox.swift`. Regenerate the
project after adding sources or changing `iOS/project.yml`.

`Scripts/build-solver-ios.sh` builds pinned COIN-OR sources as static iOS libraries;
no external solver executable or downloaded runtime is used on the device. Device
and simulator archives are separate. The sources, licenses and notices are the
same as the macOS solver; see [CBCIntegration.md](CBCIntegration.md) and
[ThirdParty.md](ThirdParty.md). The first clean build also prepares the pinned
source archives through the macOS solver script. Build products stay in `.build`.

## Verification

Run the BraidArt scheme's tests on a connected device:

```sh
xcodebuild -project iOS/BraidArt-iOS.xcodeproj -scheme BraidArt \
  -destination 'id=YOUR_DEVICE_UDID' -derivedDataPath .build/ios \
  -allowProvisioningUpdates test
```

Hosted tests exercise native weaving, shareable PNG/PDF/GLB/USDZ/ZIP payloads,
shared photo and video import, camera controls, touch recognizer configuration,
3D PNG capture, and video decoding/weaving/MP4 export with audio. The iPad UI test
exercises weaving, result pinch zoom, 3D drag/pinch, the share sheet and the Files
picker, and saves screenshots. Its synthetic fixture is enabled only in Debug
builds with `--ui-fixture`.

To check the system import handoff, share a photo or video from Files or Photos
to BraidArt, tap Done, and return to the app. Confirm the media loads in Prepare
and Weave Image is enabled once sampling completes.

Physical iPhone validation was completed on an iPhone 12 Pro Max running iOS
27.0.1. Fifteen hosted tests passed, including native solving, camera and gesture
configuration, video with audio, Photos video saving, export contents, and pause
and cancellation behavior. Seven UI tests passed across the phone verification
runs: English layout and rotation, result pinch, one-finger 3D rotation and pinch,
French tab labels in both orientations, PNG saving to Photos and Files, 3D PNG,
PDF/GLB/USDZ saving through Files, first-launch help, and extended background
pause/resume. The export tests create sample outputs in Photos and Files.

XCTest's public touch API cannot synthesize a two-finger drag. The two-finger pan
recognizer configuration and camera translation are covered by the hosted test;
the physical two-finger panning gesture still needs manual verification.

`PartitionPauseTests` covers partition-boundary pause/resume, expiration retry,
cancellation while paused, concurrent waiters, and video with audio. The device
test `testBackgroundWeaveFinishesCurrentPartThenResumesNextPart` uses a separate
Debug fixture, backgrounds the app for 55 seconds, and verifies that extended
runtime was granted, exactly the first partition completed before pausing, and
the second partition started only after activation.
