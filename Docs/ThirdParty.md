# COIN-OR solver

The components below retain their upstream licenses, author notices and source
references. See the [third-party inventory](../Licenses/README.md).

BraidArt bundles unmodified COIN-OR source releases compiled with Apple clang,
static COIN-OR libraries incorporated into the macOS solver library and the iOS
framework, plus system compression/C++ libraries. CBC runs within the app's own
process; the standalone CBC executable is not shipped.
No Homebrew runtime is required. Full license texts, author notices and origin URLs are checked into
[`Licenses/`](../Licenses/README.md) and shipped with the solver library. Each
project directory includes links to its exact release and source archive.

| Component | Version | Source |
| --- | --- | --- |
| CBC | 2.10.13 | https://github.com/coin-or/Cbc/tree/releases/2.10.13 |
| CLP | 1.17.11 | https://github.com/coin-or/Clp/tree/releases/1.17.11 |
| CoinUtils | 2.11.12 | https://github.com/coin-or/CoinUtils/tree/releases/2.11.12 |
| Osi | 0.108.11 | https://github.com/coin-or/Osi/tree/releases/0.108.11 |
| Cgl | 0.60.9 | https://github.com/coin-or/Cgl/tree/releases/0.60.9 |

The source archives and SHA-256 checksums are pinned in `Scripts/build-solver.sh`.
Each release has an EPL 2.0 top-level license and an EPL 1.0 license in its
library directory; both originals are retained, together with author notices.
The inventory also preserves embedded Bison parser, Lucent AMPL and rational
approximation notices. See [`Licenses/README.md`](../Licenses/README.md) in this
repository, or `licenses/README.md` beside this file in the app bundle.

Sources are available under the accompanying upstream licenses at the exact
release URLs above and the archive URLs recorded in each `ORIGIN.md`. They can
be downloaded, verified and built with `Scripts/build-solver.sh`. BraidArt does
not modify their source code. The packaging step copies the checked-in notices
using `Scripts/package-licenses.sh`; it does not rely on cached source folders.

Wolfram's documentation identifies CLP as its default machine-precision linear
optimization method: https://reference.wolfram.com/language/ref/LinearOptimization.html
CBC adds branch-and-cut for the notebook's integer tile variables and uses CLP
for its continuous relaxations. This does not claim Mathematica uses the same
CBC version or search settings.

No upstream implementation files are modified. `CBC_CHANGES/README.md`, included
with the solver notices, describes how any future upstream edits must be recorded
and shared. Image attribution and original source links are included in
`Licenses/README.md` and in the app's third-party credits.
