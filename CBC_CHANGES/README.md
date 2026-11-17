# Upstream solver changes

There are currently **no modified upstream solver files**. CBC and its COIN-OR
dependencies are built from the unmodified, checksum-pinned archives listed in
`Scripts/build-solver.sh` and `Licenses/*/ORIGIN.md`.

BraidArt's original library bridge is `Native/CBCBridge.cpp`; it uses upstream
public APIs and does not copy upstream implementation code.

If an upstream source edit is unavoidable:

1. Copy the file here, preserving its project and relative upstream path, for
   example `CBC_CHANGES/Cbc/Cbc/src/SomeFile.cpp`.
2. Keep the upstream copyright and license header. Record its release, original
   source URL, what changed and why in this file.
3. Build from a separate staging tree with these copies overlaid. Keep the
   extracted original source tree unchanged.
4. Include the edited copies and this record with distributed source-availability
   material and preserve the applicable upstream license. Update the packaging
   and licensing inventory in the same change.

`Scripts/package-licenses.sh` includes this directory in the app's solver notices
so any future recorded edits accompany the binary.
