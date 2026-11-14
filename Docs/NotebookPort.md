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
curve pipeline. This app stops at that boundary. `Braids.js` is retained solely
as original material; no integration or curve-file generation is attempted.
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
are intentionally distinct from raster coverage: the notebook also uses drawing
insets that do not appear in its average-color formula. Four subpixel samples
smooth the native tile raster. Width is limited to 0.6 and width+gap to 0.98 to
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
