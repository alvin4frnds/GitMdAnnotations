# Implementation Progress

Live tracker for Milestones 1a–1d of [IMPLEMENTATION.md](IMPLEMENTATION.md). Updated at the end of every milestone. The commit history is the authoritative source; this doc is the readable overview.

- Status legend: ✅ done · 🟡 in progress · ⏳ pending · ⛔ blocked

## Resuming in a fresh session

After clearing context, say: **"Resume Milestone 1b per docs/PROGRESS.md and docs/IMPLEMENTATION.md."**

Claude should then:

1. Read [`docs/IMPLEMENTATION.md`](IMPLEMENTATION.md) — authoritative plan (§2 architecture, §6.0 execution model, §6.2 M1b task list).
2. Read this file — picks up the current milestone's task board and the close-out protocol (see M1a close-out below for the pattern).
3. Pick the next `⏳` task in the active milestone's table and dispatch a fresh implementation subagent per §6.0.

### Toolchain cheatsheet (Windows + OnePlus Pad Go 2)

| Need                     | Path / command                                                            |
|--------------------------|---------------------------------------------------------------------------|
| Flutter (FVM-pinned)     | `/c/Users/Praveen/AppData/Local/fvm/fvm/fvm.exe flutter …`                |
| ADB                      | `/c/Android/Sdk/platform-tools/adb.exe`                                   |
| Tablet device id         | `NBB6BMB6QGQWLFV4` (OPD2504 / OnePlus Pad Go 2, Android 16, arm64)        |
| Deploy                   | `fvm flutter run -d NBB6BMB6QGQWLFV4 --release` (bg + Monitor for events) |
| Screenshot               | `adb -s NBB6BMB6QGQWLFV4 exec-out screencap -p > <path>.png`              |
| Tap                      | `adb -s NBB6BMB6QGQWLFV4 shell input tap <x> <y>` (device pixels 2800×1980) |
| Logcat (for crash diag)  | `adb -s NBB6BMB6QGQWLFV4 logcat -d -t 200 --pid=$(adb ... shell pidof com.praveen.gitmdannotations_tablet)` |

APP_MODE default is `mockup` (fakes seeded in bootstrap). `--dart-define=APP_MODE=real` switches to real adapters, but `_prodClientId` is still `OVERRIDE_ME` until the GitHub OAuth App is registered (see Issues.md).

### Project layout (post-M1a)

```
lib/
├── main.dart, bootstrap.dart       # APP_MODE switch, composition root
├── domain/ (entities, ports, services, fakes)   # pure Dart
├── app/ (controllers, providers)   # Riverpod 2 (no codegen)
├── infra/ (auth, git, storage, fs) # platform adapters
└── ui/ (mockup_browser, screens, theme)
test/, integration_test/            # mirror lib/ structure; integration_test/ is skipped-by-default
docs/
├── IMPLEMENTATION.md               # authoritative plan
├── PROGRESS.md                     # this file
├── Issues.md                       # deferred defects
└── PRD/                            # source of truth for requirements
```

## Current state

**Milestone:** 1a closed ✅. Next up → **1b** (annotation canvas + PDF rendering). See M1b task board below.
**Last updated:** 2026-04-20.

### Completed before 1a proper (UI spike)

- ✅ Flutter project scaffolded (`com.praveen.gitmdannotations_tablet`, Android-only, landscape-locked).
- ✅ FVM pinned to Flutter stable 3.41.7 / Dart 3.11.5 via `.fvmrc`.
- ✅ Design tokens (`lib/ui/theme/tokens.dart`) — PRD §5.11 palette, light + dark.
- ✅ `AppTheme` (`lib/ui/theme/app_theme.dart`) — Material `ThemeData` with system fonts; Inter/JetBrains Mono/Caveat bundling is a known follow-up.
- ✅ Mockup browser shell — left rail lists all 12 PRD screens, in-app theme toggle.
- ✅ All 12 PRD mockup screens composed as stubbed widgets (no real controllers yet).
- ✅ Review-panel stroke hints replaced with hand-drawn wobbly paths.

### Milestone 1a task board

Task numbering and TDD ceremony follow IMPLEMENTATION.md §5.3 and §6.0. Each task = fresh general-purpose subagent; quick review between tasks; fix critical/important before moving on.

| # | Task | Status |
|---|---|---|
| T1 | Tests for existing `AppTokens` + `context.tokens` extension | ✅ |
| T2 | Domain entities (`Job`, `SpecFile`, `Phase`, `Anchor`, `StrokeGroup`, `Commit`, `RepoRef`, `GitIdentity`, `AuthSession`) + tests | ✅ |
| T3 | `AuthPort` + `FakeAuthPort` + domain tests (Device Flow scripted, PAT, 401) | ✅ |
| T4 | `SecureStoragePort` + `KeystoreAdapter` | ✅ |
| T5 | `AuthController` (Riverpod) + state-transition tests | ✅ |
| T6 | OAuth Device Flow adapter (dio + `url_launcher`) | ✅ |
| T7 | `GitPort` + `FakeGitPort` + domain tests (conflict truth table, atomic commit) | ✅ |
| T8 | `FileSystemPort` + `FakeFileSystem` + `FsAdapter` + phase integration | ✅ |
| T9 | `SpecRepository` + `OpenQuestionExtractor` + tests | ✅ |
| T10 | Git infra adapter (`libgit2dart` isolate) + integration skeleton | ✅ (skeleton; real IT pending device seam) |
| T11 | `SyncService.syncDown` happy-path + tests | ✅ (integration test is T10 skeleton; enable after device seam) |
| T12 | Wire `SignIn` + `JobList` to real controllers (composition root) | ✅ (RepoPicker + SpecReader wiring → M1b/1c) |
| M1a-close | Milestone review + QA + triage + fix + re-QA | ✅ |

### M1a close-out

- **Deploy smoke test:** clean release build, installed on OPD2504, app launches into Sign In signed-out state.
- **QA round 1:** 23 screenshots captured; automated QA agent hit an image-dimension ceiling and was finished manually. 2 Critical/High + 6 Medium/Low findings. Report: `docs/_m1a_qa_report.md`.
- **Triage round 1:** fresh-context triage agent produced `docs/_m1a_triage.md`; 2 items marked "Fix now", 12 deferred to `docs/Issues.md`.
- **Fix round 1:** bootstrap seeds `FakeAuthPort.nextChallenge` (WDJB-MJHT) + `pollScript` + `patScript`; SignIn shows `barrierColor: Colors.black54`; extracted `PatDialog` wraps `AlertDialog` in a tokenised `Theme` + surfaceElevated background. 4 new widget tests added. 280 → 284 tests.
- **QA round 2:** device-code panel now renders `WDJB-MJHT` + caption (Fix 2 ✅); PAT dialog still black-screened on device.
- **Root cause (round 2):** OnePlus Pad Go 2's `OplusSecurityInputMethod` (its vendor secure-input keyboard) renders opaque black and covers the full Flutter surface when `autofocus: true` + `obscureText: true` co-occur on a `TextField`. Diagnosed via logcat (`ImeTracker SHOW_SOFT_INPUT` + `VRI[MainActivity] handleResized abandoned!`).
- **Fix round 2:** removed `autofocus: true` from `PatDialog` so the secure IME does not auto-invoke. Dialog now renders correctly; user taps to focus, standard keyboard animates in.
- **QA round 3:** PAT dialog renders with visible title, labeled TextField, Cancel + Sign in actions; barrier dims sidebar rather than masking it. Milestone exit criteria met for the UI paths we can exercise today.
- **Deferred to M1b / M1c / Issues.md:** real-mode OAuth integration (needs registered OAuth App), Sync Up + conflict archival, RepoPicker, markdown rendering wiring, libgit2dart migration, Inter font bundling, dark-mode re-audit. All tracked in `docs/Issues.md`.

### Milestone 1b task board — annotation canvas + PDF (pending)

Per IMPLEMENTATION.md §6.2. Fresh subagent per task; sequential execution within the milestone; close-out QA + triage loop per §6.0.

| # | Task | Status |
|---|---|---|
| T1 | `Stroke` / `StrokePoint` / `StrokeGroup` entity tests deepened (boundary cases for pressure, empty strokes, huge stroke sets) | ⏳ |
| T2 | `SvgSerializer` domain service + golden tests (scripted stroke sequences → exact SVG strings) | ⏳ |
| T3 | `AnnotationSession` state machine (begin/extend/end stroke, undo/redo ≥ 50, palm rejection against `PointerDeviceKind`) + tests | ⏳ |
| T4 | `PngFlattener` port + fake + domain tests | ⏳ |
| T5 | `AnnotationController` (Riverpod) with autoDispose per-job scoping + ProviderContainer tests | ⏳ |
| T6 | `InkOverlay` widget: `Listener` + `CustomPainter` stylus pipeline; pressure-sensitive painting | ⏳ |
| T7 | Wire real `AnnotationCanvas` screen to `AnnotationController` (replace hardcoded strokes with session state) | ⏳ |
| T8 | `PdfRasterPort` + `pdfx` adapter (lazy-load pages, LRU cache) + minimal integration test on device | ⏳ |
| T9 | `PdfPageView` widget + wire into `SpecReader` flow; PDF + overlay composition matches markdown pipeline | ⏳ |
| T10 | `PngFlattener` infra adapter (real Skia-free capture via offscreen surface) + integration test | ⏳ |
| T11 | Pen-latency measurement against NFR-1 (<25 ms p95) on OPD2504 | ⏳ |
| M1b-close | QA round + triage + Medium/Low to Issues.md | ⏳ |

### Milestones 1c–1d

See IMPLEMENTATION.md §6.3–6.4. Task boards expand here when each milestone starts.

## Change log

- 2026-04-20 — UI spike deployed; 12 screens rendering on OPD2504. PROGRESS.md initialized. Milestone 1a started.
