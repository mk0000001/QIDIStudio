# QIDI Studio SMB save responsiveness

Approved scope: the user requested the same diagnosis, isolated patch, regression tests, Windows build, public fork and upstream contribution as the Bambu investigation, starting 2026-11-03 at 04:10 Asia/Seoul. Existing approval covers continuous execution.

## Evidence and design

Upstream `QIDITECH/QIDIStudio` main is `403b619d56147160bb883e94f95a7951245bc6d0`, version `02.07.02.73`, matching the installed version. `save_project` and successful `export_3mf` both reach `set_project_filename`, `add_to_recent_projects`, `SendRecentList(0)` and a synchronous timestamp lookup for every history entry. The images argument limits thumbnails, not filesystem queries. The November 2 read-only native probe measured 248 timestamp queries in 2409.98 ms for two scans of the 124-entry QIDI history; this is component evidence, not QIDI GUI save timing.

Port the reviewed Bambu request policy (upstream PR https://github.com/bambulab/BambuStudio/pull/12850, product commit a81a1426225987e2ad735ef1618923c5c295380c). Queue/coalesce requests while the actual right-hand home browser is not shown on screen, including when another child webview is visible. Flush through the existing idle handler. Deferred nonnegative image ranges widen to INT_MAX because intervening saves can reorder entries. Preserve -1, visible ranges, order, timestamp formatting, missing-file behavior and history persistence. Do not change staff-pick/show handlers, serializer, file picker, networking or settings.

## Acceptance and safety

- Exercise the actual production policy with bundled Catch2, first failing then passing, Windows and Linux C++17.
- Independently review the entire product diff, including wx integration, initialization, child visibility and thumbnail reorder behavior.
- Attempt the complete Windows app build using published inputs; verify dependency provenance before reuse. Never fabricate omitted vendor sources or use mismatched binaries to claim a patched app.
- If a full executable can be built, test isolated account-free profiles and synthetic 3MFs on local, mapped SMB and UNC paths, dirty Ctrl+S, home thumbnails/timestamps, missing history, minimize/restore and available child browser transitions; validate ZIP CRC/XML/instance counts and reopen.
- Diagnose Save As picker and post-save delay separately. Do not claim an uncaptured picker stall fixed, or call component probes GUI evidence.
- Preserve originals, original preferences, Bambu work and previously retained SMB test files. Keep actual history paths, credentials and raw traces private. No security changes or new agreement acceptance.
- Separate focused product branch, fork-only CI and investigation docs. Request upstream beta/official-release consideration and any necessary workflow approval. Publish only accurately labeled artifacts; disclose build/GUI blockers.

## Initial build finding

The published main tree omits the ignored `src/slic3r/QIDI` and `deps/pgLibConnect` directories. `QIDI/UserPresetSyncManager.cpp` is an unconditional GUI source; the P2P import library is unconditionally linked on Windows. Setting QDT_RELEASE_TO_PUBLIC=0 (as upstream CI does) does not supply these files. Investigate published assets and capture an actual Windows build prerequisite failure rather than pretending a runnable release exists.
