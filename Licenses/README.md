# Third-party licenses and origins

This directory preserves the licenses and author notices for the third-party
projects downloaded and compiled into BraidArt's bundled COIN-OR solver. These
files are checked into the repository and copied into the app bundle.

BraidArt's original code and project-owned materials use Apache 2.0; see the
repository's [LICENSE](../LICENSE), [NOTICE](../NOTICE) and
[licensing scope](../Docs/Licensing.md). The components below retain their own
licenses and are excluded from the root Apache license. In the app bundle,
BraidArt's own LICENSE and NOTICE are in `Contents/Resources/`.

| Project | Version | Origin | Local license and authors |
| --- | --- | --- | --- |
| COIN-OR CBC | 2.10.13 | [coin-or/Cbc](https://github.com/coin-or/Cbc/tree/releases/2.10.13) | [License](Cbc/LICENSE), [library license](Cbc/LIBRARY-LICENSE), [authors](Cbc/AUTHORS), [provenance](Cbc/ORIGIN.md) |
| COIN-OR CLP | 1.17.11 | [coin-or/Clp](https://github.com/coin-or/Clp/tree/releases/1.17.11) | [License](Clp/LICENSE), [library license](Clp/LIBRARY-LICENSE), [authors](Clp/AUTHORS), [provenance](Clp/ORIGIN.md) |
| COIN-OR CoinUtils | 2.11.12 | [coin-or/CoinUtils](https://github.com/coin-or/CoinUtils/tree/releases/2.11.12) | [License](CoinUtils/LICENSE), [library license](CoinUtils/LIBRARY-LICENSE), [authors](CoinUtils/AUTHORS), [provenance](CoinUtils/ORIGIN.md) |
| COIN-OR Osi | 0.108.11 | [coin-or/Osi](https://github.com/coin-or/Osi/tree/releases/0.108.11) | [License](Osi/LICENSE), [library license](Osi/LIBRARY-LICENSE), [authors](Osi/AUTHORS), [provenance](Osi/ORIGIN.md) |
| COIN-OR Cgl | 0.60.9 | [coin-or/Cgl](https://github.com/coin-or/Cgl/tree/releases/0.60.9) | [License](Cgl/LICENSE), [library license](Cgl/LIBRARY-LICENSE), [authors](Cgl/AUTHORS), [provenance](Cgl/ORIGIN.md) |

The exact releases contain an **EPL 2.0** top-level `LICENSE` and an **EPL 1.0**
`<project>/LICENSE`. Both files are preserved verbatim. This inventory reports
what the source releases contain; it does not replace their individual notices.
Each project's `ORIGIN.md` links its repository, exact release, source archive,
license files and author files, and records the source archive's SHA-256 checksum.
Unmodified source code is available under the accompanying licenses at those
URLs. `Scripts/build-solver.sh` downloads and verifies those exact archives.

## Additional upstream notices

- **GNU Bison generated parser**, embedded in CoinUtils's
  `CoinUtils/src/CoinModelUseful2.cpp`: [origin and exception](Bison/ORIGIN.md),
  [original generated-parser notice](Bison/GENERATED-PARSER-NOTICE.txt), and
  [complete GPL v2 text](Bison/GPL-2.0.txt). The upstream notice grants a special
  exception for the generated output. Bison itself is not shipped in the app.
- **Lucent AMPL interface notice**, present in
  [CBC's Cbc_ampl.cpp](https://github.com/coin-or/Cbc/blob/releases/2.10.13/Cbc/src/Cbc_ampl.cpp)
  and [CLP's Clp_ampl.cpp](https://github.com/coin-or/Clp/blob/releases/1.17.11/Clp/src/Clp_ampl.cpp):
  [CBC notice](Cbc/AMPL-NOTICE.txt) and [CLP notice](Clp/AMPL-NOTICE.txt), including
  copyrights, permission and warranty disclaimer. BraidArt disables ASL/AMPL
  support during the build; the notices are retained for completeness.
- **Rational approximation attribution**, in
  [CoinUtils's CoinRational.cpp](https://github.com/coin-or/CoinUtils/blob/releases/2.11.12/CoinUtils/src/CoinRational.cpp):
  [original notice](CoinUtils/RATIONAL-NOTICE.txt). It credits Matthew Saltzman
  and Ted Ralphs, EPL 1.0, and John D. Cook's
  [original algorithm](https://www.johndcook.com/blog/2010/10/20/best-rational-approximation/),
  used by upstream with permission.

## Other provenance

The six CIEDE2000 reference pairs in `Tests/BraidCoreTests/CoreTests.swift` come
from Gaurav Sharma, Wencheng Wu and Edul N. Dalal's supplementary numerical
validation data:

- [Authors' CIEDE2000 resource page](https://hajim.rochester.edu/ece/sites/gsharma/ciede2000/)
- [Original numerical test data](https://hajim.rochester.edu/ece/sites/gsharma/ciede2000/dataNprograms/ciede2000testdata.txt)
- Paper: *The CIEDE2000 Color-Difference Formula: Implementation Notes,
  Supplementary Test Data, and Mathematical Observations*, Color Research &
  Application 30(1), 21–30 (2005), [DOI 10.1002/col.20070](https://doi.org/10.1002/col.20070).

The Swift and Metal implementations were written for BraidArt; upstream MATLAB
or other implementation code was not copied. No third-party code license is
invented for these numerical reference values.

The original Mathematica notebooks and `Braids.js` were supplied by the project
owner. Their repository origin is [christophe0606/BraidArt](https://github.com/christophe0606/BraidArt).
Project-owned notebook code and scripts are covered by BraidArt's Apache 2.0
license; separately identified third-party material retains its own terms.
Mathematica and Blender are not bundled. Apple frameworks and the system's
libc++, zlib and bzip2 libraries are linked from macOS, not copied into the app.

## App bundle

`Scripts/package-licenses.sh` copies this entire directory, with the origin URLs,
into `BraidArt.app/Contents/Resources/Solver/licenses/` and includes the overview
as `BraidArt.app/Contents/Resources/Solver/ThirdParty.md`. Packaging reads these
checked-in notices even when the downloaded source/build cache is unavailable.
