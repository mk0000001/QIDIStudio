# QIDI SMB Save Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to implement this plan task by task, with one independent whole-branch review.

**Goal:** Remove redundant hidden-home recent-project scans from QIDI saves and submit a verified, accurately scoped contribution.

**Architecture:** A header-only request policy feeds the existing WebViewPanel idle handler. Only a visible target browser consumes pending work; no new threads or callbacks.

**Tech Stack:** C++17, wxWidgets, bundled Catch2, CMake, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-11-03-qidi-smb-save.md`.

## Global Constraints

Preserve source version 02.07.02.73 and save semantics. No private paths/configuration/traces in public content. Keep Bambu work and original files untouched. No security weakening. Do not label an unbuilt app a tested binary. Execute the previously approved scope without asking again.

## Review Focus

1. Parent visible but home child hidden: no metadata scan; verify real m_browser visibility guard.
2. Two hidden saves reorder images: deliver both thumbnails; test deferred image range INT_MAX.
3. Initial full refresh followed by save: do not narrow; test pending INT_MAX plus 0 and -1.
4. Repeated idle or hide/show: no duplicate dispatch; test consumption and subsequent requests, inspect wx lifecycle.
5. Public builds and debug builds: flush outside QDT_RELEASE_TO_PUBLIC condition; inspect actual source and Windows build prerequisites.

### Task 1: Port policy with regression coverage

**Files:** Create `src/slic3r/GUI/RecentProjectsRefresh.hpp`, `tests/slic3rutils/recent_projects_refresh_tests.cpp`; modify WebViewDialog.cpp/.hpp and tests/slic3rutils/CMakeLists.txt.

**Interfaces:** `request(int images)` and `take(bool ready) -> std::optional<int>`. SendRecentList queues then calls private FlushRecentList; idle calls FlushRecentList; visible guard uses actual m_browser.

- [ ] Copy the six reviewed behavioral tests first; compile against bundled Catch2 before adding the header. Expected: missing production header (RED).
- [ ] Port the minimal policy and integration; retain all existing handlers. Compile/run focused C++17 tests on WSL. Expected: 6 cases / 21 assertions pass. Check diff and commit only five product files.

### Task 2: Independent review and public CI/build attempt

**Files:** Fork-only `.github/workflows/smb-save-validation.yml`, `.github/smb-validation/CMakeLists.txt`, build prerequisite check, investigation report.

**Interfaces:** CI compiles the exact Task 1 test/source files; clean product branch remains independent of CI/docs.

- [ ] Dispatch one read-only fresh reviewer with spec, plan, product base/head and Review Focus. Address important findings with RED/GREEN evidence.
- [ ] Run focused tests on Windows/Linux; attempt full Windows build after validating published source prerequisites. Expected: focused suites pass; app either compiles or records exact missing vendor input. Do not mask a failure.
- [ ] Verify artifact hashes and contents. Publish an executable only if it is actually built from the reviewed source and checked.

### Task 3: Native validation or precise blocker

**Files:** Investigation report and private ignored validation scratch.

**Interfaces:** Consumes full app from Task 2 if available; no substituted baseline executable.

- [ ] For a valid patched executable run isolated synthetic local/mapped/UNC Save As and Ctrl+S, home/recent/thumbnail/missing/minimize tests and ZIP/XML/reopen checks.
- [ ] If vendor inputs block a patched executable, record the missing inputs and unexecuted matrix explicitly; retain component measurements as such. Inspect installed baseline/picker only where it produces new evidence.

### Task 4: Submit contribution

**Files:** Fork investigation docs and upstream PR description.

**Interfaces:** Upstream PR contains five product files only; links to independent test/build evidence and exact source.

- [ ] Refresh checks and inspect final product diff/private-data hygiene.
- [ ] Create upstream PR and request next beta/official consideration, disclosing any unavailable full build/native validation and requesting maintainer inputs/CI approval.
- [ ] Attach PR to chat and report concrete results plus blockers. Preserve review workspace while follow-up is needed.
