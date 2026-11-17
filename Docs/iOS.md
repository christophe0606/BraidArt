# BraidArt for iPhone and iPad

The native iOS app shares BraidCore, the app model, settings, crop editor, video
playback and Metal/SceneKit renderer with the macOS app. It requires iOS/iPadOS 26
or later; the Mac app continues to support macOS 14 (Sonoma) or later.

- iPad: landscape, with a resizable settings sidebar on the left. Drag its handle
  to change its width; the sidebar button in the toolbar hides or restores it.
  Width and visibility are remembered across launches.
- iPhone: portrait and landscape, with Prepare, Tile Library, Result, 3D and Settings tabs.
- 3D: drag with one finger to rotate, two fingers to pan, and pinch to zoom.
- Result: pinch to zoom and drag the enlarged picture; Fit resets the view.
- Open pictures and videos through the standard Photos picker or Files picker.
- Pictures and woven videos offer Photos or Files when exported. PDF, GLB, USDZ,
  project and data exports use Files only. Photos access is requested only when
  saving to Photos, and requires add-only access. If permission is refused, the
  completed export remains available through Files. The export toolbar button
  appears only in Result and 3D, separately from Weave Image.
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

The checked-in Xcode project can also be opened directly. Select your development
team in Xcode if different from the repository's existing local team. Regenerate
the project after adding sources or changing `iOS/project.yml`.

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

Hosted tests exercise native weaving, picture export destinations, PDF/GLB/USDZ
Files exports, camera controls, touch recognizer configuration, 3D PNG capture,
and video decoding/weaving/MP4 export with audio. The iPad UI test exercises
weaving, result pinch zoom, 3D drag/pinch, destination choice and the Files picker,
and saves screenshots. Its synthetic fixture is enabled only in Debug builds
with `--ui-fixture`. Photos authorization/saving and two-finger panning should also
be checked manually. Physical iPhone testing follows iPad acceptance.

`PartitionPauseTests` covers partition-boundary pause/resume, expiration retry,
cancellation while paused, concurrent waiters, and video with audio. The device
test `testBackgroundWeaveFinishesCurrentPartThenResumesNextPart` uses a separate
Debug fixture, backgrounds the app for 55 seconds, and verifies that extended
runtime was granted, exactly the first partition completed before pausing, and
the second partition started only after activation.
