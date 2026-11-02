# QIDI Studio SMB save investigation — 2026-11-03

## Result and scope

The five-file source patch is published at [fix/smb-save-recent-refresh](https://github.com/mk0000001/QIDIStudio/tree/fix/smb-save-recent-refresh), commit `e709341ba83ce32d70c5fd03937c984b7d79da6d`, tree `9c00807aa5ddc78547dbd8d824bae4476f0f2bf5`. It defers the hidden home browser's recent-project metadata refresh. It does not make archive writing asynchronous and does not fix the separately reported Save As picker stall.

Both Windows and Linux focused regression jobs passed in [validation run 41508902641](https://github.com/mk0000001/QIDIStudio/actions/runs/41508902641). **No patched QIDI GUI executable has been built or released.** The Windows application job failed its published-input preflight; application compilation and packaging were skipped. Native patched GUI tests therefore remain blocked.

## Matched source and diagnosis

- Official upstream: `QIDITECH/QIDIStudio`, main `403b619d56147160bb883e94f95a7951245bc6d0`, source and installed application version `02.07.02.73`.
- `Plater::save_project` (`Plater.cpp:18585`) calls `export_3mf` then `set_project_filename` (`:18613`). The successful interactive export also calls `set_project_filename`. Each reaches `MainFrame::add_to_recent_projects` (`MainFrame.cpp:4406`) and `WebViewPanel::SendRecentList(0)`.
- `SendRecentList` immediately called `get_recent_projects` before this patch. That function (`MainFrame.cpp:4477`) iterates every entry and calls `boost::filesystem::last_write_time`; image zero does not limit the filesystem loop. The GUI thread pays this cost while the editor hides the home page.
- QIDI has additional child browsers and a login overlay compared with Bambu. Checking the actual `m_browser->IsShownOnScreen()` avoids scanning while another child view is shown. The existing idle binding runs in public and debug configurations; no new event lifetime or worker is introduced. Existing staff-pick/show handlers are untouched.
- Save As uses `wxFileDialog` (`Plater.cpp:10607`). The dependency manifest tracks `bambulab/wxWidgets` master, without identifying the installed binary's exact dependency revision. No new long picker stall or causal stack was captured in this run. The earlier Bambu file-I/O trace did not capture that long stall either; it is not QIDI-specific GUI evidence.

## Tests and measurements

The six Catch2 cases exercise the actual production policy: hidden deferral, widest range, visible range merging, preserving the -1 argument, consuming once then accepting later requests, and A/B saves reordering thumbnail indices. The initial compile failed because the new production header was absent; adding the policy and wx integration yielded 21 passing assertions in six cases using GCC 13.3, C++17, `-Wall -Wextra -pedantic`.

CI uses the repository's bundled Catch2 and exact product test/header. [Linux job](https://github.com/mk0000001/QIDIStudio/actions/runs/41508902641/job/125495288043): GNU 13.3.0, passed. [Windows job](https://github.com/mk0000001/QIDIStudio/actions/runs/41508902641/job/125495288523): MSVC 19.44.35229, passed. CTest registers one executable containing all six cases. The repository's complete application-linked test suite has not run because full build inputs are unavailable. A local WSL CMake wrapper attempt could not start because CMake is not installed there; the direct GCC run and both CI CMake runs did execute.

Windows diagnostic artifact `13171478178` contains only `recent_projects_refresh_tests.exe` and `recent_projects_refresh_probe.exe`; these are **not the QIDI application**. Its downloaded ZIP matched SHA256 `e32694ce12dfa9e49e8d9228b9ee487cebc8c2202a4eb41e1408cc90172db1f0`, and its contents were checked before extraction/execution. Running that test executable locally also passed 21 assertions / six cases.

A fresh read-only Windows probe used the current 124-entry QIDI history, without printing or uploading any paths. It models the Windows timestamp API sequence and uses the real patched request policy:

| Component operation | Timestamp queries | Observed time |
|---|---:|---:|
| Two original history scans | 248 | 2260.38 ms |
| Two hidden refresh notifications | 0 | 0.0001 ms |
| Consume refresh on return home | 124 | 1055.54 ms |

These are a single component benchmark, not GUI save durations, hung-window measurements or end-to-end proof. The current history and network cache affect timing. The earlier November 2 probe observed 2409.98 ms for the same 248-query pattern. Returning home still performs a synchronous scan.

## Full application build blocker

The Windows job [failed the explicit input check](https://github.com/mk0000001/QIDIStudio/actions/runs/41508902641/job/125495288521) with exit 1. Required inputs absent from both published main and the matching release tree include:

```
src/slic3r/QIDI/UserPresetSyncManager.cpp
src/slic3r/QIDI/UserPresetSyncManager.hpp
deps/pgLibConnect/Lib/Windows/pgDllConnect.lib
```

`src/slic3r/CMakeLists.txt:244–245` lists the preset manager unconditionally, and `:771` links the Windows P2P import library unconditionally. The matching directories are also in upstream `.gitignore`. Upstream CI's `QDT_RELEASE_TO_PUBLIC=0` excludes some other network sources but does not satisfy these requirements. Existing reports [#120](https://github.com/QIDITECH/QIDIStudio/issues/120) and [#126](https://github.com/QIDITECH/QIDIStudio/issues/126) concern older missing network sources; they do not prove this exact current failure but show related build limitations were previously reported.

No reusable public upstream Actions artifacts were returned when checked. No matching SDK headers/import library were found in the installed runtime directory. The Windows/Linux source dependencies also differ from Bambu's, so Bambu's prebuilt dependency archive was not substituted. Building third-party dependencies cannot supply missing QIDI sources/import libraries; the fork fails before that expensive step. This is a build prerequisite failure, **not a completed full application compilation attempt or a successful build**.

To continue: maintainers need to publish the matching preset manager implementation/header and P2P SDK build inputs (or a supported build path without them), or build this focused branch with their available inputs. No fabricated implementations, unrelated networking removal or runtime binary patching were used.

## Independent review and remaining work

An independent read-only whole-product review found no Critical, Important or Minor defects. It inspected child visibility, thumbnail reordering, initial full refresh, repeated idle consumption, GUI lifecycle and both compile configurations. It did not run a native GUI.

Decisions retained after review: preserve the existing serializer's signed/unsigned handling of -1 (the helper preserves the argument, not a new payload guarantee); keep archive/history persistence/thumbnail extraction synchronous; leave the separate picker investigation unresolved. Widening hidden nonnegative ranges prevents dropped thumbnails at the cost of sending all images when home becomes visible.

| Requested native check | QIDI patched-app status |
|---|---|
| Local / mapped SMB / UNC Save As and dirty Ctrl+S | Blocked: no patched executable |
| Long history, missing items, home timestamps and A/B thumbnails | Policy tested; native GUI blocked |
| Minimize/restore and available child browser transitions | Source reviewed; native GUI blocked |
| Saved ZIP CRC/XML/model counts and reopening | Blocked: no patched executable |
| Save As long-stall cause | Unresolved; no claimed picker fix |

Original projects/preferences and Bambu work are untouched. Actual recent paths, configuration, credentials and raw trace data stay local. The source/workspace is retained for maintainer feedback and the missing-input follow-up.
