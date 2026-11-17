# BraidArt for macOS, iPhone and iPad

A native SwiftUI app for the image-to-dark-tile pipeline in
`TilingAndConstraints.nb` and the curve generation pipeline in `3DBraids.nb`.
Requires macOS 14 or later. The locally built app targets Apple Silicon;
building on an Intel Mac produces an Intel app and solver.

## iPhone and iPad

The universal app requires iOS/iPadOS 26 or later. It uses a landscape workspace with a settings sidebar on iPad,
and portrait/landscape tabs on iPhone. It supports touch controls for 2D/3D and
Photos or Files for picture/video exports. PDF and 3D objects export through Files.
See [iOS build and testing instructions](Docs/iOS.md).

## Run on macOS

Open **`dist/BraidArt.app`** in Finder after building. The app includes CBC and
requires neither Mathematica nor Homebrew at runtime. This development build is
locally signed, not notarized.
The build registers `.braidart` files as **BraidArt Project** documents with
macOS. Double-click a project in Finder to open it in BraidArt.
Replace any older copy in `/Applications` with the newly built bundle so Finder
uses the current icon and document declaration.
Projects use the BraidArt icon. The document type is app-specific data rather
than a text type, so it does not request Quick Look's JSON/text preview.
The File menu follows the familiar macOS order: **Open…**, **Close**, **Save…**,
then **Export**. **Help → BraidArt Help** introduces the app with a photograph of
astronaut Eileen Collins: the original photograph, a cropped portrait, its woven
picture and its 3D artwork. The NASA photograph is public domain, as documented
by [scikit-image](https://scikit-image.org/docs/stable/api/skimage.data.html#skimage.data.astronaut).
The interface, help, progress messages and app errors use standard macOS
localization: French for French language preferences, and English as the
development language and fallback. macOS also supports a per-app language choice
in System Settings. Translations are in
`Sources/BraidCore/Resources/{en,fr}.lproj/Localizable.strings`; Finder document
names use `Resources/{en,fr}.lproj/InfoPlist.strings`. Original third-party
license documents and project/export data retain their original text.

The About window links to the [original photograph](https://flic.kr/p/r9qvLn)
and NASA’s media usage guidelines.

1. Choose **Open Image, Video or Project**, or drag an image or video from Finder onto the
   main window. Saved projects can also be dropped onto the window. Choose
   **Output dimensions** (Full HD by default) to set the final woven PNG size and
   its aspect ratio. Opening a picture displays the largest centered crop with
   that ratio. Drag inside the rectangle to move it, or drag any edge
   or corner to resize it. Pinch or use the **− / +** buttons above the picture to
   scale the crop while preserving its proportions. The ratio stays locked when
   drawing, resizing or scaling. Drag outside the crop to draw another rectangle.
   **Reset Crop** (or Delete while the crop editor is focused) restores the largest
   centered crop with the selected ratio. Set the image width in tiles. The height
   follows the crop's aspect ratio, with a maximum of 256 tiles on either axis.
   Tile size in pixels is calculated from the output dimensions and tile count;
   there is no separate PNG tile size setting. Fractional tile sizes are supported
   so the final PNG always has exactly the selected dimensions. 3D geometry still
   uses one unit per tile; 3D camera pictures retain their separate size picker.
   The built-in list includes 720p, 1080p, 1440p, 4K UHD, 4K vertical, TikTok /
   YouTube Shorts (1080 × 1920), and Instagram Reels, feed, square and landscape
   video formats. These names describe canvas dimensions for images and videos.
   Dimensions menus separate image, video and user-defined formats into groups.
   Use **Manage Dimensions…** (the sliders button beside either dimensions picker)
   to add a named size, or edit and delete your custom sizes. Built-in sizes are
   locked. Custom sizes are saved across app launches and are available for both
   woven PNGs and 3D pictures. Deleting a selected custom size selects 1080p Full HD.
   Saved projects carry their selected dimensions, so they still open correctly
   on another Mac without your custom-size library.
2. Start with black and white strands over a gray background, or set a maximum
   of two to eight colors and select **Extract** to find representative colors
   in the cropped image. **Color separation** controls how similar shades are
   combined: **Keep shades**, **Low**,
   **Medium** (the default), or **High**. Higher separation may return fewer colors
   than requested. **Include small accents** (on by default) selects colors by
   perceptual diversity from a detailed sample of the crop, preserving small
   features such as muted eye colors, highlights and lip colors. Turn it off to
   favor the largest image regions. Use six to eight colors when several small
   details matter; the default maximum is six. Extraction uses the same crop,
   brightness, contrast and grayscale adjustments as the tile image. Projects
   without the original picture use their saved sampled image. Select **Extract**
   after changing these settings. Extract also fits the background against the
   prepared picture using the selected strands and their geometry. The background
   must remain at least the **Background contrast** threshold from every retained
   strand so none disappears into it. This slider ranges from 1 to 50 CIEDE2000
   units, defaults to 15, and is saved with the project. Increase it for more
   obvious strands, then select **Extract** to apply. **Reset** restores 15.
   Extract preserves all strand colors when possible; if a
   dense palette leaves no suitable background, it omits the fewest conflicting
   colors found by the search. Within that visibility constraint it minimizes
   sampled nearest-tile CIEDE2000 error, including the uncovered area of each tile;
   this estimate does not include the solver's strand continuity constraints.
   Luminance mode selects both the strand shades and background from the full
   black-to-white range, without color casts.
   Edit any strand
   or the background with its color picker. The tile library shows all `4 × colors²`
   combinations. New sessions start with **Luminance only** enabled; turn it off
   for color artwork. Existing projects restore their saved mode. Luminance,
   contrast, brightness and alpha compositing are applied before sampling.
3. Click **Weave Image**. Parts are solved in the notebook's order with top and
   left continuity fixed by previous parts. Progress and Cancel remain available.
   Time and relative-gap limits support interactive use. Every returned part is
   checked for integral choices and valid edge colors before acceptance.
4. Inspect the result and zoom in. **Save Project** stores a `.braidart` JSON
   project, including the 3D camera's rotation, zoom and pan, backing plane
   settings, and selected picture dimensions. Reopening restores that camera
   in the 3D view; older projects without a saved camera open in Result.
   The original full-resolution source picture is not embedded.
   All export commands are in **File → Export**, directly below
   **Save…**. **Result as PNG…** renders at the selected output dimensions.
   **Solution and Tile Data…** creates a self-contained folder of JSON, Wolfram data and tile
   PNGs. The export dialog chooses a parent directory and creates a fresh child
   folder without overwriting an earlier export.
   Its `result.png` uses the same output dimensions. Individual tile PNG sizes
   are derived from the grid and rounded to whole pixels.
5. For a video source, the timeline below the source picture has two orange
   handles to trim the segment start/end and a playhead to select a test frame.
   Click the timeline or drag the playhead to scrub. **Play segment** loops the
   selected segment until you pause it. The crop remains visible and interactive
   over the moving video, so you can resize or move it while watching the loop.
   **Weave Image** captures the current playhead frame, pausing playback when
   necessary. Color extraction also uses that frame. Weave a frame from the
   selected segment and inspect it in **Result** before starting a video run.
   **Weave Video…** and its format/audio controls appear only in **Result**.
   Changing the processing settings requires another frame weave. Choose
   **Most compatible (H.264 / MP4)**, **H.264 High Profile**, or **H.265 / HEVC**.
   **Include audio** is enabled by default; turn it off to create a silent video.
   The dimensions picker sets the exact movie dimensions; video width and height
   must be even numbers from 16 to 8192 pixels.
   **Weave Video…** asks for the destination before any video weaving starts.
   Only the selected segment is decoded and solved, one frame at a time, with
   the same fixed crop, palette and processing settings. Source timing is retained
   relative to the segment start, including a partial first/last frame. When enabled, the first
   audio track is re-encoded as stereo AAC. A progress window includes **Cancel**;
   cancellation stops the solver and removes temporary output, preserving any
   existing destination. The completed video is saved directly to the chosen MP4.
   Saved projects retain a woven frame, not a link to the source video; reopen
   the video and check a frame to start another video run.
6. Open **3D** to view continuous, colored tube meshes rendered through Metal.
   Drag to rotate; Shift-drag, right-drag or middle-drag to pan; scroll or pinch
   to zoom. **Front / Fit** resets the camera; **Perspective** gives an angled
   view. Set the backing plane color and its clearance from the lowest tube.
   These settings are retained in the project. Use **Picture dimensions** to
   select a PNG size. A red rectangle over the 3D view marks exactly the area
   that will be exported; rotate, pan and zoom to compose inside it. The frame
   follows the viewport when you resize the window and is not included in the PNG.
   **File → Export → 3D View as PNG…** saves the
   current 3D view as a PNG, including its angle, zoom, pan, lighting and backing
   plane. The size menu and save panel share the same selection: current viewport, HD
   (1280 × 720), Full HD (1920 × 1080), 4K UHD (3840 × 2160), or Instagram
   square (1080 × 1080), portrait (1080 × 1350), tall portrait (1080 × 1440),
   landscape (1080 × 566), and Story (1080 × 1920). Pictures are rendered at the
   selected resolution after **Save**; a progress window includes **Cancel**.
   The camera is frozen when you open the export panel, preserving your zoom,
   rotation and pan. A different output aspect ratio crops the visible view
   to the centered red frame without changing the live camera.
7. **File → Export → Vector PDF…** writes a single page of filled strand contours with
   fine black outlines, edged underpass ends and no embedded images. Generation
   starts after you choose a destination and click **Save**. A progress window
   includes **Cancel**; cancelling preserves any existing destination file.
   **File → Export → 3D Object (GLB)…** saves the same tube meshes and backing plane with normals and colored
   PBR materials in a self-contained glTF 2.0 file.
   Import the GLB directly in Blender using **File → Import → glTF 2.0**.
   It contains the strand geometry, backing plane and material colors; no script
   is required.
7. **File → Export → 3D Object (USDZ)…** saves a self-contained colored object for Apple
   Motion, with the same strands and backing plane centered around its anchor.
   Export begins after **Save**, with progress and **Cancel**. In Motion, choose
   **File → Import → Media** and select the `.usdz` file. Use Motion's own
   cameras and lighting to position and animate the object.

A saved project retains the exact sampled image, complete tile definitions,
settings, solution and per-part solver reports. Reopen it to change the palette,
geometry or solver settings and solve again. Reopen the original picture to
change image preparation; its full-resolution pixels are not embedded.
Changing settings preserves the last successful result until another solve
succeeds; the UI identifies results belonging to earlier settings.

## Build and test

Requires Xcode 16 or later / Swift 6, the command-line tools and `pkg-config` for
the source solver build (`brew install pkgconf` if it is absent). Downloading the
pinned COIN-OR sources requires internet access. No other Swift packages are used.

```sh
./Scripts/build-solver.sh
./Scripts/build-app.sh
swift test --disable-sandbox --scratch-path .build/swift
open dist/BraidArt.app
```

Help opens automatically on the first launch for each macOS user. The app saves
`hasShownFirstLaunchHelp` in its `org.braidart.mac` preferences. To test the first
launch again, quit BraidArt, then run from the repository directory:

```sh
defaults write org.braidart.mac hasShownFirstLaunchHelp -bool false
open dist/BraidArt.app
```

Only this flag is reset; other preferences are preserved. After the help opens,
the flag becomes `true` again. To inspect it:

```sh
defaults read org.braidart.mac hasShownFirstLaunchHelp
```

The automatic help also appears once for existing users upgrading from a version
without this preference. It remains available through **Help → BraidArt Help**.

The solver script verifies pinned SHA-256 checksums, compiles CBC/CLP and their
COIN-OR dependencies with Apple clang, and installs only under `.build/`. It
builds static COIN-OR libraries and links them into `libBraidCBC.dylib`, with
macOS 14 as the deployment target. Bundle
licenses and exact upstream versions are listed in [Docs/ThirdParty.md](Docs/ThirdParty.md).
Open `Package.swift` in Xcode for editing and debugging after building the solver.
Debug builds load `.build/solver-native/lib/libBraidCBC.dylib`; packaged apps load
it from `Contents/Frameworks`. CBC executes in the application process with
cooperative cancellation; no solver executable or Homebrew installation is
required at runtime. Upstream sources remain unmodified. See
[the library integration notes](Docs/CBCIntegration.md) for error handling,
threading and verification.
`Scripts/build-app.sh` creates
a standalone Finder bundle with native document opening, menus and local signing.

For distribution outside the Mac App Store, follow the short one-time Xcode and
Keychain setup in [Distributing BraidArt](Docs/Distribution.md), then run
`./Scripts/release-app.sh`. It builds, signs, notarizes and creates a distribution
ZIP using credentials kept in Keychain. Normal development builds continue to
use local ad hoc signing and need no Developer ID certificate.

## Implementation and notebook compatibility

- Core Image performs oriented, color-managed cropping, alpha flattening,
  adjustment and Lanczos resizing. No full-resolution image enters the optimizer.
- Metal computes the full pixel-by-tile CIEDE2000 error table on the GPU. A CPU
  implementation handles systems where Metal is unavailable. The UI's result
  footer records which implementation was actually used.
- CBC performs mixed integer optimization on CPU threads using CLP for LP
  relaxations. CLP is the open-source solver identified in Wolfram's documentation;
  the binary constraints in this notebook need CBC's integer layer as well.
- `VCross`, `HCross`, `CircLeft` and `CircRight` use the same color pair order,
  analytic area weights, edge signatures and drawing offsets as `mkDarkTiles`.
- IDs are **one-based**, solutions are `solution[row][column]`, and rows run from
  the **top** of the image to the bottom. Palette indices in JSON tile definitions
  are zero-based. `data.wl` reconstructs notebook-shaped `solution` and `tileData`,
  including `allTiles`, `allTilesImg`, `tileColorValue`, `topologyH` and `topologyV`.
  Load it using `Get["/path/to/data.wl"]` before subsequent notebook processing.

See [Docs/NotebookPort.md](Docs/NotebookPort.md) for equations, source locations
and practical limits. The original notebooks and JavaScript are untouched.
Curve tracing, Bézier generation, vector PDF, Metal visualization and GLB export
are implemented. Blender itself has not been launched or tested.

## Third-party credits

Third-party components retain their own licenses, author notices and source
references. The application does not display or bundle an open-source license
for BraidArt itself.

Full license texts, author notices, exact upstream source URLs and archive
checksums for all five COIN-OR components are in [Licenses/README.md](Licenses/README.md).
The notices also cover embedded Bison parser and AMPL code and cite the numerical
color-validation data. The app bundle includes the same license inventory.

## About and inspiration

Choose **BraidArt → About BraidArt** for Christophe Favergeon's copyright,
included third-party projects with their source links and license texts, and
the source/rights information for the help illustrations.

The app icon uses exactly nine connected tiles in a 3 × 3 arrangement, with
broad black and white strands on gray, rendered by BraidArt's own flat tile
renderer. The tiny generated source is `Resources/IconSource.png`; the validated
repeating source pattern is
`Resources/IconPattern.braidart`. `Resources/AppIcon.png` is the cropped master.
Every tile boundary and constant-color curve is checked before rendering.
Regenerate the artwork and all macOS icon sizes with `Scripts/generate-icon.sh`.
The generation details are recorded in `Resources/AppIcon.source.txt`.
The same icon is bundled for the Dock, sidebar, About, Help and Finder documents,
including when launching directly from VS Code or Xcode.

Inspired by [*Opt Art: From Mathematical Optimization to Visual Design* by
Robert Bosch](https://press.princeton.edu/books/hardcover/9780691164069/opt-art)
(Princeton University Press, 2019). BraidArt uses a substantially different
implementation with additional features.
