# BraidArt for macOS

A native SwiftUI app for the image-to-dark-tile pipeline in
`TilingAndConstraints.nb` and the curve generation pipeline in `3DBraids.nb`.
Requires macOS 14 or later. The locally built app targets Apple Silicon;
building on an Intel Mac produces an Intel app and solver.

## Run

Open **`dist/BraidArt.app`** in Finder after building. The app includes CBC and
requires neither Mathematica nor Homebrew at runtime. This development build is
locally signed, not notarized.

1. Choose **Open Image or Project**. Drag over the source to crop it; use **Reset
   Crop** to restore the full picture. Set the image width in tiles. The height
   follows the crop's aspect ratio, with a maximum of 256 tiles on either axis.
2. Start with black and white strands over a gray background, or **Extract** two
   to eight dominant colors from the sampled image. Edit any strand or the
   background with its color picker. The tile library shows all `4 × colors²`
   combinations. **Luminance only**, contrast, brightness and alpha compositing
   are applied before sampling.
3. Click **Weave Image**. Parts are solved in the notebook's order with top and
   left continuity fixed by previous parts. Progress and Cancel remain available.
   Time and relative-gap limits support interactive use. Every returned part is
   checked for integral choices and valid edge colors before acceptance.
4. Inspect the result and zoom in. **Save Project** stores a `.braidart` JSON
   project; **Export PNG** renders a higher-resolution picture. **Export Solution
   & Tile Data** creates a self-contained folder of JSON, Wolfram data and tile
   PNGs. The export dialog chooses a parent directory and creates a fresh child
   folder without overwriting an earlier export.
5. Open **3D** to view continuous, colored tube meshes rendered through Metal.
   Drag to rotate; Shift-drag, right-drag or middle-drag to pan; scroll or pinch
   to zoom. **Front / Fit** resets the camera; **Perspective** gives an angled
   view. Set the backing plane color and its clearance from the lowest tube.
   These settings are retained in the project. **Export Picture…** saves the
   current 3D view as a PNG, including its angle, zoom, pan, lighting and backing
   plane. Choose the output size in the save panel: current viewport, HD
   (1280 × 720), Full HD (1920 × 1080), 4K UHD (3840 × 2160), or Instagram
   square (1080 × 1080), portrait (1080 × 1350), tall portrait (1080 × 1440),
   landscape (1080 × 566), and Story (1080 × 1920). Pictures are rendered at the
   selected resolution after **Save**; a progress window includes **Cancel**.
   The camera is frozen when you open the export panel, preserving your zoom,
   rotation, pan and field of view. A different output aspect ratio crops or
   extends the visible area at the sides without changing the camera.
6. **Export Vector PDF** writes a single page of filled strand contours with
   fine black outlines, edged underpass ends and no embedded images. Generation
   starts after you choose a destination and click **Save**. A progress window
   includes **Cancel**; cancelling preserves any existing destination file.
   **Export 3D Object
   (GLB)** saves the same tube meshes and backing plane with normals and colored
   PBR materials in a self-contained glTF 2.0 file.
   Import the GLB directly in Blender using **File → Import → glTF 2.0**.
   It contains the strand geometry, backing plane and material colors; no script
   is required.

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

The solver script verifies pinned SHA-256 checksums, compiles CBC/CLP and their
COIN-OR dependencies with Apple clang, and installs only under `.build/`. It
builds static COIN-OR libraries with macOS 14 as the deployment target. Bundle
licenses and exact upstream versions are listed in [Docs/ThirdParty.md](Docs/ThirdParty.md).
The app can also use an existing CBC executable through **Choose CBC Executable**
or the `BRAIDART_CBC` environment variable.

Open `Package.swift` in Xcode for editing and debugging. A source-run app finds
`.build/solver-native/bin/cbc` when its working directory is the repository;
otherwise choose that executable in the interface. `Scripts/build-app.sh` creates
a standalone Finder bundle with native document opening, menus and local signing.

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

## License

BraidArt's original code and project-owned materials are licensed under the
[Apache License, Version 2.0](LICENSE). See [NOTICE](NOTICE) for project attribution
and [Docs/Licensing.md](Docs/Licensing.md) for the licensing scope.

Third-party components retain their respective licenses. In particular, the
separate COIN-OR solver is distributed under its upstream licenses; the root
Apache license does not relicense it.

Full license texts, author notices, exact upstream source URLs and archive
checksums for all five COIN-OR components are in [Licenses/README.md](Licenses/README.md).
The notices also cover embedded Bison parser and AMPL code and cite the numerical
color-validation data. The app bundle includes the same license inventory.

## About and inspiration

Choose **BraidArt → About BraidArt** for Christophe Favergeon's copyright,
the project license, and included projects with their source links and license
texts.

The app icon is bundled as a Swift package resource and used explicitly in the
Dock and About window, including when launching directly from VS Code or Xcode.

Inspired by [*Opt Art: From Mathematical Optimization to Visual Design* by
Robert Bosch](https://press.princeton.edu/books/hardcover/9780691164069/opt-art)
(Princeton University Press, 2019). BraidArt uses a substantially different
implementation with additional features.
