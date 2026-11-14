# Licensing scope

BraidArt's original code and project-owned materials are licensed under the
[Apache License, Version 2.0](../LICENSE). The project attribution and dependency
summary are in [NOTICE](../NOTICE). Separately identified third-party components
and reference materials retain their own terms; the root Apache license does
not replace their licenses or copyright notices.

## Current integration

The SwiftUI app communicates with the unmodified CBC command-line executable
through temporary LP and solution files. It does not copy COIN-OR source into
the Swift/Metal implementation or link COIN-OR libraries into the app executable.
CBC's own executable incorporates the COIN-OR libraries and keeps their upstream
licensing. This separation allows BraidArt's original application code to be
licensed under Apache 2.0 while distributing the solver under its respective
licenses.

The exact solver releases contain EPL 2.0 top-level licenses and EPL 1.0 library
licenses. Both are preserved with author notices, embedded-code exceptions,
exact source URLs and archive checksums in [Licenses/](../Licenses/README.md).
The source is available under those upstream licenses at the linked releases;
`Scripts/build-solver.sh` downloads, verifies and builds the unmodified archives.
The Bison-generated parser retains its explicit output exception. ASL/AMPL
support is disabled; its upstream notices are retained as well.

## Distribution

The repository and packaged app include the Apache license and project notice,
as well as the separate third-party license inventory. Keep those notices,
source-availability information and upstream licenses when redistributing the
bundle. Changes to upstream code must follow that component's own terms.

This scope covers the current separate-executable architecture. Incorporating
third-party implementation code into BraidArt would require checking the
licensing of that change.

## Primary references

- [Apache License 2.0](https://www.apache.org/licenses/LICENSE-2.0)
- [Eclipse EPL FAQ, especially questions 22 and 25–27](https://www.eclipse.org/legal/epl/faq/): source remains under EPL; separate modules may use their own license.
- [EPL 2.0 text](https://www.eclipse.org/legal/epl-2.0/): definitions of contributions and modified works, and source-distribution requirements.
- [Apache Software Foundation third-party policy](https://www.apache.org/legal/resolved.html#category-b): EPL 1.0/2.0 binary components can be included with appropriate labeling. This is supporting guidance from the ASF; BraidArt is an independent project, not an ASF project.
