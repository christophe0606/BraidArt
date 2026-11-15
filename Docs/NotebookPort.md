# Notebook port and numerical behavior

## Source map

The owning definitions are in `TilingAndConstraints.nb`. Line numbers refer to
the original copied notebook, not extracted Wolfram source.

| Notebook definition | Original line | Native implementation |
| --- | ---: | --- |
| ImageCrop / ImageResize / ImageAdjust | 19659 / 20162 | ImageProcessing.swift |
| createTileData, topology groups | 40040 | Models.swift |
| drawVCross, drawHCross, drawCircLeft, drawCircRight | 40401–40617 | TileRenderer.swift |
| mkDarkTiles | 40736 | TileData.init(settings:) |
| darkKnotAverageColor, analytic weights | 40778 | TileData.init(settings:) |
| dkTop / dkBottom / dkLeft / dkRight | 40888 | Tile edge signatures |
| costPixel with CIE2000 | 41597 | ColorScience.swift / ColorCost.metal |
| solvePb and binary domain | 41716 | PartitionSolver.makeProblem |
| partitionSolve | 41924 | PartitionSolver.solve |
| createPict | 42094 | TileRenderer.render |

`3DBraids.nb` lines 1761–1801 use the same dark-tile solve, with part size 7.
Lines 24090 onward save `solution` and `tileData` before the different subsequent
curve pipeline. `Curves.swift` now traces the two pieces per tile across matching
edges, starting with boundary paths and then closed loops. It uses an iterative
walk, including paths that revisit a tile through its other strand. GLB is the
3D interchange format. `Braids.js` remains unmodified historical material.
`Tools/extract_notebook.py` is a read-only aid for extracting textual input boxes;
it is not a Wolfram evaluator or a general notebook converter.

## Tile definitions

Background is `g`; the two strand colors are `a,b`. Types are generated in order
VCross, HCross, CircLeft, CircRight, with all ordered palette pairs inside each.

| Type | Top | Right | Bottom | Left | Weight a | Weight b |
| --- | --- | --- | --- | --- | --- | --- |
| VCross | b | a | b | a | 1−w−gap | w |
| HCross | b | a | b | a | w | 1−w−gap |
| CircLeft | a | b | b | a | πw/4 | πw/4 |
| CircRight | b | b | a | a | πw/4 | πw/4 |

The average is `(1−weightA−weightB)g + weightA*a + weightB*b` in encoded sRGB,
matching notebook arithmetic. Default width is 0.414 and gap 0.4. Analytic weights
are intentionally distinct from raster coverage. The native raster uses centered
straight strands and quarter circles of radius 1/2, all with width `w`, so adjoining
tiles meet smoothly. The notebook's small drawing offsets and unequal widths are
omitted to avoid steps at curved-to-straight joins. Four subpixel samples smooth
the native tile raster. Width is limited to 0.6 and width+gap to 0.98 to
keep weights and strand geometry valid.

## Optimization

A binary variable `x[p,t]` chooses tile t at sampled pixel p.

```
minimize sum(p,t) CIEDE2000(sample[p], average[t]) * x[p,t]
subject to
  sum(t) x[p,t] = 1                         for every pixel
  x[p,t] in {0,1}
  sum(t with right(t)=c) x[p,t]
    = sum(t with left(t)=c) x[p+right,t]    for each horizontal edge and color c
  sum(t with bottom(t)=c) x[p,t]
    = sum(t with top(t)=c) x[p+below,t]     for each vertical edge and color c
```

The last color equality is redundant with the per-pixel sum and is omitted to
reduce model size. Boundary pixels must choose a tile matching the neighbor's
already-fixed edge color. Part order matches `partitionSolve`: first row, first
column, then row-major interior. Remainder parts retain their actual dimensions.
There is no outside border closure constraint, just as in the source notebook.
Independent part optima do not constitute a global whole-image optimum.

LP output uses continuation lines of at most 200 bytes for the objective,
constraints and binary declarations. This avoids a CoinUtils 2.11.12 parser
failure when a long physical line ends exactly at a 1023-byte buffer boundary.
Only whitespace changes; all coefficients, tile choices and constraints remain
the same.

CBC receives a valid greedy incumbent, so an interactive time limit can still
produce a usable integer solution. A time- or gap-limited incumbent is labeled
feasible; a solution reported optimal within gap tolerance is not called proven
optimal. All one-hot choices, internal edges and incoming boundaries are checked
again after parsing CBC output. No fractional relaxation is rounded into a tile
map. Cancel terminates only the app's running solver process and removes its
per-part temporary files. A watchdog stops a solver that overruns its limit.

## Color handling

Images are oriented from metadata and converted to sRGB by Core Image. Costs use
Lab D50 (Bradford-adapted sRGB), consistent with Wolfram's documented default
white point. Exact RGB neutrals use zero Lab chroma to prevent tiny floating
point errors from introducing arbitrary hue. CIEDE2000 uses unit parametric
factors. The CPU implementation is checked against Sharma–Wu–Dalal reference
pairs; Metal and CPU costs are compared on neutral and colored palettes.

This preserves the metric and the notebook's model, not binary-identical
Mathematica results. Core Image resampling, color profiles, GPU float versus CPU
double, tie breaking and solver time/gap policies can choose different valid
tiles. No live Mathematica numerical comparison has been run. Dominant colors
use deterministic Lab k-means rather than Wolfram's proprietary DominantColors.

## Limits and build

The sampled grid is capped at 256×256 and the palette at 8 colors (256 candidate
tiles). Cost-table allocation is capped at 32 million entries. Parts range from
1 to 20 tiles per side, time limits from 1 to 600 seconds, and CPU threads from
1 to 16. Large palettes and parts can still be expensive mixed integer problems.
Start with 50 columns, two colors and parts of 7. The app limits raster export
to 80 megapixels and offers 20, 50 or 100 pixels per tile.

The development app is ad-hoc signed and not notarized. The bundled solver links
only macOS system libraries. A distribution build would require the owner's
Developer ID signing and notarization. No signing identity or account ID is
stored in the repository.

## References

- [Wolfram LinearOptimization and CLP](https://reference.wolfram.com/language/ref/LinearOptimization.html)
- [Wolfram ColorConvert white points](https://reference.wolfram.com/language/ref/ColorConvert.html)
- [COIN-OR CBC](https://github.com/coin-or/Cbc)
- [Sharma–Wu–Dalal CIEDE2000 implementation notes and reference data](https://hajim.rochester.edu/ece/sites/gsharma/ciede2000/)

## Curves, PDF and 3D

`3DBraids.nb` defines `analyzeTile` at line 86, tracing at 24153, quarter-circle
Béziers at 25139, crossing controls at 25324, spline conversion at 25552, the
stream writer at 26876 and “Generate file” calls at 27229–27238. Native curves preserve open
ends, loop closure and palette indices. Coordinates use the notebook convention:
tile centers start at (1,-1,0), XY is the image plane and positive Z faces the
viewer. Corner arcs have radius 1/2 and cubic factor `4(sqrt(2)-1)/3`.

The notebook’s eight crossing controls form two cubic segments. Their Z values
are scaled so the midpoint height is `max(0.3353863185193847, 1.1*strandWidth)`;
XY controls retain their original values. This differs deliberately from the
old Blender importer’s fixed radius of 0.207107−0.05 and Z offset of −0.05.
Native 3D tubes use radius `strandWidth/2`, with smooth vertex normals and capped
open ends. The same tessellation is used for Metal and GLB. Default sampling is 16 radial
sides and 16 steps per cubic; large grids reduce this to 10/8 above 4096 tiles
and 8/4 above 16384 tiles to bound memory use. This is a visual
mesh, not a guaranteed intersection-free CAD solid for arbitrary tile settings.
Analytic curves are regenerated from the saved project’s tiling when opened.

Vector PDF projects the generated curves into XY. Raised pieces project to
straight lines. Underpasses are split using the configured crossing gap, and
each visible strand is expanded into a filled vector contour with a fine black
outline, 0.02 tile wide. The outside strand width is preserved by insetting the
outline center. Exposed cut ends are outlined too. Connected pieces and closed
loops remain continuous across tile boundaries and the tracing origin. The PDF
background is the solved tile background; the independently editable backing
plane belongs to 3D. A tile spans 24 PDF points and the page follows the tiling’s
aspect ratio. The PDF uses no bitmap drawing or embedded image resources.

`BraidMetalView` is an SCNView explicitly configured with the Metal renderer.
It displays indexed tube geometry with PBR materials, directional lights and
shadows, an ambient fill and a backing plane. Clearance is the distance from
the lowest strand surface to the plane, so its Z is `−strandWidth/2−clearance`.
Camera fit, orbit, pan and zoom act on the camera, leaving exported geometry
unchanged. Plane settings are optional in version-1 projects for backward
compatibility; old projects default to their tile background and 0.15 clearance.

The 3D workspace’s Export Picture action freezes the current camera before the
save panel opens, then renders a lossless PNG in the background at the selected
resolution. Zoom, rotation, pan, field of view, lights and backing plane are
retained, without the surrounding app UI. A different output aspect ratio crops
or extends the visible area at the sides without refitting the camera.

GLB stores triangles, normals and materials with no external files. sRGB colors
are converted to linear RGB for glTF base-color factors. It retains geometry
and color. Import it directly in Blender using File → Import → glTF 2.0;
no separate curve export or importer script is needed. The imported strands
are triangle meshes.

USDZ exports the same indexed meshes and vertex normals in a centered component,
with explicit MaterialBindingAPI bindings and linear RGB USD Preview Surface
materials. A buffered USDA writer streams the geometry into a self-contained,
uncompressed ZIP package with CRC-32 and 64-byte payload alignment. It needs no
external converter. Progress and cancellation remain available; the destination
is replaced atomically only after the complete package is ready. In Apple Motion,
import the file using File → Import → Media, then use Motion's cameras and lights.

Validation covers all four tile kinds, mixed-color seams, reversed paths, closed
loops, paired triangle edges and normalized normals,
GLB chunks/materials, USDZ geometry/color round trips and cancellation, old/new
project loading and PDF image-resource absence.
A Metal snapshot test renders real geometry and exercises camera and plane
updates. PDF output is also rendered with Poppler and checked with `pdfimages`.
Blender has deliberately not been run.

Format references: [glTF 2.0 specification](https://registry.khronos.org/glTF/specs/2.0/glTF-2.0.html)
and [USDZ specification](https://openusd.org/release/spec_usdz.html).
