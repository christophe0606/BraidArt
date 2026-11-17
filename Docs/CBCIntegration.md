# In-process CBC integration

BraidArt calls CBC inside the application process. It does not launch the CBC
executable. `Scripts/build-solver.sh` builds the pinned, unmodified COIN-OR
libraries and links them into `libBraidCBC.dylib` with the BraidArt-owned bridge
in `Native/CBCBridge.cpp`. The app links this shared library and packages it in
`Contents/Frameworks`. Its remaining dependencies are Apple system libraries. Packaging removes any
development-checkout or Xcode-toolchain runtime search paths before signing;
the distributed executable resolves the solver from its own framework directory.
The bridge exports a small C interface declared in
`Sources/CBCLibrary/BraidCBC.h`; no C++ exceptions cross that interface.

The partition model, greedy MIP start, command-driver defaults, CBC thread count,
time/gap settings, solution parsing, and top/left seam validation are retained.
Each request uses its own temporary directory for its LP, MIP start, solution,
and diagnostic files. Files are removed after success, cancellation or error,
after the native call has finished. All paths are absolute; the bridge does not
change the app's working directory or redirect its standard output/error.
The driver imports the already validated LP to initialize its private name table
for the standard solution writer, avoiding any patch to upstream CBC.

## Cancellation and threading

A dedicated dispatch worker executes each native call so the main actor and
Swift's cooperative executor remain free. A native mutex serializes calls to the
CBC command driver, which has global parser state. CBC may still use its own
configured solver threads within a call. Cancelling a queued request does not
cancel the active one or consume the queued partition's time allowance.

Swift task cancellation sets a request-owned atomic flag. Derived CBC and CLP
event handlers observe it during branch-and-bound and LP solving, respectively.
Handlers clone with solver models and the driver callback reattaches them after
preprocessing. The driver callback also checks cancellation between phases.
CBC's process-wide SIGINT handler is explicitly disabled.

Cancellation is cooperative: a library operation without an event callback must
return before cancellation completes. The UI stays busy until the native solver
has unwound, its worker threads have finished and temporary files are removed.
Swift discards a result if cancellation races native completion. The existing
image result is retained; the video exporter retains its atomic-save cleanup.

CBC's elapsed-time limit remains the normal per-partition stopping mechanism;
a feasible time-limited incumbent remains usable. Event/stage handlers also
check a monotonic deadline with the previous 20-second cleanup allowance. This
is a cooperative deadline, not a process-kill watchdog.

## Failure handling and limits

The bridge validates BraidArt's limited LP grammar before entering the upstream
reader, including section order, coefficients, variable references, binary
declarations, line lengths and truncation. This avoids a native reader crash
observed with malformed input, without editing CoinUtils. It also checks
arguments, LP import, seed availability, driver return status,
and solution-file availability. It catches `CoinError`, standard C++ exceptions
(including allocation errors), and other C++ exceptions and returns an error
code and bounded diagnostic text. Swift reports these errors and cleans files.
The existing solution parser rejects infeasible, fractional, malformed or
incorrectly connected solutions. A later request gets a new model and can run
after cancellation or a recoverable error.

An in-process library cannot safely recover from arbitrary native memory
corruption, `abort()` or fatal signals. Such a CBC failure can terminate BraidArt;
we do not install signal traps or attempt unsafe recovery. The bridge accepts
only a fixed command sequence and disables optional ASL/GLPK integrations at
build time; it does not expose arbitrary CBC commands. Full crash isolation
would require a separate process, which is outside this architecture.

## Upstream source and licensing

No upstream CBC, CLP, Cgl, Osi or CoinUtils implementation file is modified.
The bridge and event subclasses are original Apache-2.0 application code using
public APIs. Upstream components keep their own licenses; see `Docs/Licensing.md`
and `Licenses/README.md` for notices and exact source archives.

If an upstream edit becomes necessary, follow `CBC_CHANGES/README.md`: retain the
edited copy and its upstream path/version there and distribute it with the
corresponding source-availability information. Do not edit cached originals.

## Verification

Build native dependencies before running Swift builds or tests:

```sh
./Scripts/build-solver.sh
swift test --disable-sandbox --scratch-path .build/swift
./Scripts/build-app.sh
```

`CBCLibraryTests` exercises real native cancellation with one and four threads,
cancellation before entry and while waiting for another request, temporary-file
cleanup, malformed/missing input and unwritable output, recovery, concurrent and
repeated calls, signal-handler preservation, and time-limited feasible results.
The existing partition tests check brute-force optimality, variable names,
large palettes and both incoming seams. Video tests exercise the same library
path across frames and cancellation.

The current build targets macOS 14 and the host architecture. An iOS/iPadOS port
must build the native sources for those SDKs and package the dynamic library as
a framework. This change does not add mobile targets or App Store distribution.
