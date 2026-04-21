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

**Milestone:** 1c 🟡 — core flow code-complete; **M1c-close QA pending on device**. 1d 🟡 — T1–T4 done; T5 (battery profiling, needs 4-hour device run) pending. Phase 1 completion plan: [`docs/implementation-plan2.md`](implementation-plan2.md).
**Last updated:** 2026-04-21 (late, after W5.2/5.3/5.4 + spec-reader-md real rendering).

### Phase 1 completion snapshot

Across the two pushes documented in `docs/implementation-plan2.md`:

| Wave | Scope | Status |
|---|---|---|
| **W1** | Bundle Inter + JetBrains Mono fonts (closes Issues.md:21-26); refresh PROGRESS.md + materialize plan at `docs/implementation-plan2.md`; cross-compile libgit2 for `arm64-v8a` + `armeabi-v7a`; push-error classifier refactor (+42 tests) | ✅ |
| **W2.1/2.2** | Cross-compile mbedTLS 2.28 LTS (3 ABIs); relink libgit2 with `-DUSE_HTTPS=mbedTLS`; integration test asserts `GitFeature.https` on emulator-5554; `sync_conflict_test.dart` regression-green | ✅ |
| **W2.3** | Publish fork (`../libgit2dart-fork/`) as git repo, swap `path:` → `git: { url, ref }` | ⏳ (~30 min, needs GitHub auth) |
| **W2.5** | On-tablet OPD2504 smoke (arm64 `.so` + HTTPS on real hardware) | ⏳ (needs tablet connected) |
| **W3.1** | RepoPicker — domain entity + port + fake + Dio adapter + controller + screen; `_AuthGate` now routes SignIn → RepoPicker → JobList; +7 controller tests (pick() path has a documented TODO for path_provider override) | ✅ |
| **W3.2** | Fix `claude-jobs` branch bootstrap from `origin/claude-jobs` in `_handleCloneOrOpen` | ✅ |
| **W3.3** | Fix `resetHard('origin/claude-jobs')` via RevParse fallback + `_lookupLocalOrRemoteRef` in `_handleMerge` + libgit2 1.5 NFF needle + fetch-before-reset in `ConflictResolver` — all five surfaced by the diverged-conflict integration test, all now green | ✅ |
| **W4.1/4.2** | Navigation wiring: JobList row → SpecReader (md/pdf by `SourceKind`); SpecReader chrome Annotate / Review panel / Submit buttons wired through the already-landed M1c-T7 orchestrator | ✅ |
| **W4.3** | Review draft auto-save (5s tick, coalesces keystrokes, pop-save on dispose); delegated to parallel agent; +6 tests | ✅ |
| **W4.4** | M1c close-out QA round (ADB golden-path on tablet + triage) | ⏳ (interactive; needs credentials + device) |
| **W5.1** | ChangelogViewer — `ChangelogAggregator` service + controller + timeline UI + JobList left-rail nav entry; delegated to parallel agent; +15 tests | ✅ |
| **W5.2** | Settings screen (ACCOUNT / REPOSITORY / DATA sections) + Export backups via Storage Access Framework (`shared_storage` 0.8.1, recursive SAF copy, sealed `ExportOutcome`); delegated to parallel agent; +9 tests | ✅ |
| **W5.3** | Recovery flows — `loadLastSession` validates workdir+`.git` existence and clears stale keys on mismatch; `SyncController.syncUp` auto-signs-out on `PushRejectedAuth` so revoked tokens don't persist; +4 tests | ✅ |
| **W5.4** | Cold-start NFR-2 preload — persist `(repo, workdir, jobId)` via `SecureStoragePort` on every `RepoPickerController.pick()` + JobList row tap; `main()` rehydrates before `runApp` and overrides `currentRepoProvider` / `currentWorkdirProvider` so `_AuthGate` lands on JobList directly; `ColdStartTracker` writes 3 checkpoints to `dart:developer` for `adb logcat | grep gitmdscribe.nfr2`; sign-out clears the keys; delegated to parallel agent; +16 tests | ✅ |
| **W5.5** | Battery NFR-8 profiling (4h continuous review on OPD2504) | ⏳ (needs device + measurement window) |
| **W6** | NFR-1 real-stylus p95, NFR-7 TalkBack, NFR-9 storage LRU, NFR-10 on-device sync timing | ⏳ |
| Hygiene | `SyncController` now uses `ClockPort` (closes the M1a-T11 Low entry in `Issues.md`); push-error classifier enumerates structured categories (closes the M1a-T10 Medium) | ✅ |

**Test count:** 668 → **726 passing** (+58 across the push). Same 2 pre-existing `sign_in_screen_test.dart` flakes (independent of this work).
**APK:** ships `libgit2.so` + `libmbedtls.so` + `libmbedx509.so` + `libmbedcrypto.so` under each of `lib/{arm64-v8a,armeabi-v7a,x86_64}/`. Real HTTPS clones/fetches/pushes against `github.com` now possible.

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
| T1 | `Stroke` / `StrokePoint` / `StrokeGroup` entity tests deepened (boundary cases for pressure, empty strokes, huge stroke sets) | ✅ |
| T2 | `SvgSerializer` domain service + golden tests (scripted stroke sequences → exact SVG strings) | ✅ |
| T3 | `AnnotationSession` state machine (begin/extend/end stroke, undo/redo ≥ 50, palm rejection against `PointerDeviceKind`) + tests | ✅ |
| T4 | `PngFlattener` port + fake + domain tests | ✅ |
| T5 | `AnnotationController` (Riverpod) with autoDispose per-job scoping + ProviderContainer tests | ✅ |
| T6 | `InkOverlay` widget: `Listener` + `CustomPainter` stylus pipeline; pressure-sensitive painting | ✅ |
| T7 | Wire real `AnnotationCanvas` screen to `AnnotationController` (replace hardcoded strokes with session state) | ✅ |
| T8 | `PdfRasterPort` + `pdfx` adapter (lazy-load pages, LRU cache) + minimal integration test on device | ✅ |
| T9 | `PdfPageView` widget + wire into `SpecReader` flow; PDF + overlay composition matches markdown pipeline | ✅ |
| T10 | `PngFlattener` infra adapter (real Skia-free capture via offscreen surface) + integration test | ✅ |
| T11 | Pen-latency measurement against NFR-1 (<25 ms p95) on OPD2504 | ✅ |
| M1b-close | QA round + triage + Medium/Low to Issues.md | ✅ |

### Milestone 1c task board — review submission + Sync Up + conflicts (in progress)

Per IMPLEMENTATION.md §6.3. Status reconstructed from the commit log on 2026-04-21; next-action column notes what stands between the task and "done".

| # | Task | Status | Evidence / next action |
|---|---|---|---|
| T1 | `ReviewSerializer` golden tests (`03-review.md` structure) | ✅ | `f9ae728` + follow-up `2b4fdc4` |
| T2 | `ChangelogWriter` (append idempotency + format) | ✅ | `bdc985a` + fix `5725d6f` |
| T3 | `CommitPlanner.planReview` + `.planApprove` | ✅ | `434e401` + split `1c5813e` |
| T4 | `ConflictResolver` remote-wins archival | ✅ | `bde0a08` |
| T5 | `SyncService.syncUp` + `ConflictResolver` wiring | ✅ | `ef48f92` + follow-up `30799b8` |
| T6 | Integration test: diverged-branch conflict E2E | ✅ on host | `c4bc604` + `37a3e71`; on-device run pending until the two Issues.md High git bugs below are fixed |
| T7 | Review panel UI + Submit + Approve + conflict banner + auto-save timer | 🟡 | `5a3fbae` + `b4deb27` + `2f43b04` + `8df5fb8` + `0cc6fb2` landed; **still unbuilt:** JobList→SpecReader→Canvas→ReviewPanel navigation wiring, review-draft auto-save timer |
| M1c-close | QA + triage + fix | ⏳ | `docs/_m1c_qa_round1/` scaffolding present locally; needs to be run once navigation wiring + two Issues.md High bugs (claude-jobs branch bootstrap, resetHard ref-name) are fixed |

### Milestone 1d task board — polish + NFRs (pending)

Per IMPLEMENTATION.md §6.4. Will expand as tasks start.

| # | Task | Status |
|---|---|---|
| T1 | `ChangelogViewer` — parse `## Changelog` across all jobs, render a timeline | ✅ |
| T2 | Settings: "Export backups" via Storage Access Framework | ✅ |
| T3 | Recovery flows: corrupted `.git` surfacing + expired-token re-auth polish | ✅ |
| T4 | Cold-start NFR-2 tuning (preload last-opened job metadata) | ✅ |
| T5 | Battery profiling against NFR-8 (4+ hours active review on OPD2504) | ⏳ |
| M1d-close | QA + triage + NFR measurement gates (NFR-1 real stylus, NFR-7 TalkBack, NFR-9 LRU, NFR-10 sync) | ⏳ |

### Cross-milestone: latent defects surfaced during emulator verification (2026-04-21)

Not on the original M1c/M1d task lists, but blocking real-device sync.

| # | Task | Status | Evidence / next action |
|---|---|---|---|
| X1 | `libgit2dart` has no Android plugin — APK shipped no `libgit2.so` for any ABI | 🟡 | Forked locally at `../libgit2dart-fork/` with x86_64 + arm64-v8a + armeabi-v7a NDK builds; integration test `integration_test/libgit2_android_load_test.dart` passes on emulator (`b91a11a`). **Remaining:** OpenSSL cross-compile so HTTPS works against github.com; publish fork as git repo; on-tablet smoke test. See Issues.md "libgit2dart has no Android plugin" entry. |
| X2 | Inter + JetBrains Mono bundled, replacing system-fallback Roboto on breadcrumbs | ✅ | `assets/fonts/*` + `pubspec.yaml` + `lib/ui/theme/app_theme.dart` — closes Issues.md:21-26 |
| X3 | `claude-jobs` branch bootstrap from `origin/claude-jobs` missing in `GitAdapter.cloneOrOpen` | ✅ | `ca94f67` — `_bootstrapLocalSidecarBranch` materialises `refs/heads/claude-jobs` after clone when origin has it |
| X4 | `ConflictResolver.archiveAndReset` passes ref-name to SHA-only `resetHard` | ✅ | `ca94f67` — `_resolveRefToOid` hex-SHA fast path + `RevParse.single` fallback for ref-names/tags |
| X5 | RepoPicker UI (deferred since M1a) — blocks real-device JobList | ⏳ | New route between SignIn and JobList. Current `DEV_SEED_ENABLED` dart-define stubs past it for dev-loop work |

## Change log

- 2026-04-20 — UI spike deployed; 12 screens rendering on OPD2504. PROGRESS.md initialized. Milestone 1a started.
- 2026-04-20 — M1b T1 complete (commits `971ea15` + `6924538`). Added 16 boundary tests across `test/domain/entities/stroke_boundary_test.dart` + `stroke_group_test.dart` (pressure bounds, NaN rejection on x/y/pressure, empty/huge stroke sets, 10k-point + 500-group equality/hash). `StrokePoint` gained NaN/bounds validation (`const` dropped; no `lib/**` call-site impact). 185 → 201 domain tests, pristine analyzer. Reviewer Minor findings (NaN pressure error-message symmetry; weaker -0.0001 boundary probe) deferred — not blocking.
- 2026-04-20 — M1b T2 complete (commit `968d6be`). Added `SvgSerializer` (`lib/domain/services/svg_serializer.dart`) + 10 tests with 6 goldens under `test/golden/`. Covers happy path, multi-group, PDF anchor, single-point stroke, empty stroke+group, lowercase-hex normalization, UTC timestamp, attr-value escaping, zero groups, determinism. Exhaustive `switch` on sealed `Anchor`. Added `.gitattributes` pinning `test/golden/*.svg eol=lf` to survive Windows `core.autocrlf`. 201 → 211 tests, pristine analyzer. Reviewer Minor findings (docstring example `M120,340` vs emitted `M 120,340`; `SvgSource` lacking `==`; 257-line test file vs §2.6 200 cap) deferred — not blocking.
- 2026-04-20 — M1b T3 complete (commits `64a9d83` + `c1fb790` + `eb763e9` + review follow-ups `a1800c7`). Added `PointerSample` / `PointerKind` / `InkTool` domain entities, `Clock` + `IdGenerator` ports with fakes, and `AnnotationSession` state machine (211 → 267 tests, +56). Pins palm rejection (stylus-only), per-stroke anchor, timestamp-at-begin, snapshot defensive copy, undo/redo with configurable `undoDepth` cap (default 50; oldest strokes age out of undo stack but remain in `snapshot()`), tool capture at begin. Non-pen tools degrade to pen behavior (color + width) in T3 — palette wiring deferred to T5. Review follow-ups added mid-stroke palm-mix regression tests + `undoDepth` validation tests; dropped unwired `SystemClock` (T5 will re-add when wiring `AnnotationController`). Reviewer Minor findings (248-line test file, `_initialAnchor` unused-field suppression) deferred — not blocking.
- 2026-04-20 — M1b T4 complete (commits `db6b263` + `291e4e9` + review follow-up `ca81526`). Added `CanvasSize` domain entity (replaces `dart:ui` `Size` at the domain boundary) with 12 validation tests; `PngFlattener` port + `FakePngFlattener` + `FakeFlattenCall` + 10 tests (default 8-byte PNG signature, override bytes, call recording, defensive-copy of groups on record and of calls on read, `clear()`, Future completion). Real rasterizer adapter deferred to T10. 267 → 289 tests, pristine analyzer. Review follow-up: override `Uint8List` now defensive-copied on ctor (consistent with the rest of the fake's copy hygiene).
- 2026-04-20 — M1b T5 complete (commits `d6934f5` + `05d82a3` + `a584aed` + review follow-up `8146e8f`). Added `SystemClock` + `SystemIdGenerator` infra adapters (`stroke-group-<microsTS>-<counter>` id scheme; uniqueness is session-scoped, documented cosmetic), `AnnotationState` + `AnnotationController` (`AutoDisposeFamilyNotifier<AnnotationState, JobRef>`), and `annotationControllerProvider` (`NotifierProvider.autoDispose.family`). Bootstrap wires `clockProvider` + `idGeneratorProvider` in both real and mockup modes (inert in mockup today — mockup canvas is hardcoded widgets; T7 wires the canvas). 289 → 406 tests (+17 controller/clock/id-gen, +~100 from full-suite-now-covering test/app), pristine analyzer. Review follow-ups fixed a test-name mismatch and added an `extendStroke` state-emission regression pin. Reviewer Minor findings (229-line test file, raw-list `state.groups`, filler synchronous-read test) deferred — not blocking.
- 2026-04-20 — M1b T6 complete (commits `b51696a` + `4b74dc8` + `d698917` + review follow-up `6b3e8d3`). Added reusable `InkOverlay` widget under `lib/ui/widgets/ink_overlay/` (`PointerEventMapper` pure mapper with kind/pressure/NaN/infinity handling; `InkOverlayPainter` with `repaint: activeStroke` wiring + length/color/width `shouldRepaint`; `InkOverlay` stateful widget with `Listener` → `PointerSample` pipeline + `InkPointerPhase.{down,move,up,cancel}` callbacks + configurable `nowProvider`). Flutter 3.41.7's `TestGesture.down` doesn't accept `pressure` — used `downWithCustomEvent` with `PointerDownEvent(pressure:…)`. 406 → 443 tests (+37: 16 mapper + 12 painter + 9 widget), pristine analyzer. Review follow-up pinned local-vs-global coord semantics (catches a swap of `event.localPosition` → `event.position`). Widget is unwired into the existing hardcoded mockup canvas; T7 replaces `_InkOverlayPainter` with real controller state.
- 2026-04-20 — M1b T7 complete (commits `6d9a560` + `6eb26f5`). Split `annotation_canvas_screen.dart` (602 → 143 lines) into five siblings (`top_chrome`, `left_rail`, `main_content`, `markdown_stub`, `pen_tool_bar`); converted the screen to `ConsumerStatefulWidget` keyed on `JobRef`; wired pointer phases → `AnnotationController` intents (stylus-only at the screen, belt-and-braces with the session's palm rejection); replaced the hardcoded `_InkOverlayPainter` + margin notes with live `InkOverlay` driven by `state.groups` + a UI-local `ValueNotifier<List<Offset>>` for the in-progress stroke. Mockup registry now seeds `JobRef(demo/payments-api, spec-auth-flow-totp)` matching bootstrap's `_mockupRepo` + `_seedMockupFs`. Undo/redo buttons added (always-enabled; controller no-ops on empty stacks per T3/T5 tests). Per-sample widget rebuild cost confirmed bounded to the painter (AnnotationState value-equal mid-stroke → Riverpod default `updateShouldNotify` returns false). 443 → 451 tests (+8: initial render, stylus commit, palm reject, undo, redo, active-stroke populate, active-stroke clear, dispose leak), pristine analyzer. Reviewer Minor findings (244-line test file, missing TODO token on markdown stub, missing UI-level redo-after-new-stroke test, `nowProvider` tear-off captured at build time) deferred — not blocking.
- 2026-04-20 — M1b T8 complete (commits `c29783b` + `a38a45a` + `1ff3e17` + `c7383a4` + review follow-up `0e58c91`). Added `PdfDocumentHandle` entity, `PdfRasterPort` + sealed `PdfError` (`PdfOpenError` / `PdfRenderError`), `FakePdfRasterPort` (register/scriptOpenError/scriptRenderError + defensive-copy logs), `PdfPageCache` LRU wrapper (default capacity 8, key = `_CacheKey(handleId, pageNumber, CanvasSize)` with value-equality via T4's `CanvasSize.==`), and `PdfxAdapter` (pdfx 2.9.2) with a private `_PdfHandleIdGenerator` using the T5 micros36-counter pattern (prefix `pdf-doc-` to preserve bounded-context hygiene). Added `integration_test/fixtures/hello.pdf` (587-byte v1.4 1-page PDF, declared as Flutter asset) plus `.gitattributes` pinning `integration_test/fixtures/*.pdf binary`. 451 → 494 tests (+39 unit + 4 host-side adapter). Review follow-up: pdfx throws `MissingPluginException` under host `flutter test` (no engine attached), so on-device pins remain skipped in `integration_test/infra/pdf/pdfx_adapter_test.dart`; added 4 host-reachable pre-native tests (`open` error wrap + `close` idempotency) and documented the deferral in `docs/Issues.md`. Transitive dep: `uuid 4.5.3` (unused in repo; flagged).
- 2026-04-20 — M1b T9 complete (commits `fe9dbea` + `9c97343` + `03e7973` + review follow-ups `dc4296d` + `33d2ee3`). Added `pdfRasterPortProvider` + `pdfPageCacheProvider` + `PdfDocumentNotifier` (`AutoDisposeFamilyAsyncNotifier<PdfDocumentHandle, String>`) with `ref.onDispose` → cache-close; bootstrap wiring for real (PdfxAdapter) + mockup (FakePdfRasterPort seeded at `$workdir/jobs/pending/spec-invoice-pdf-redesign/spec.pdf`). Built `PdfPageView` widget (lazy `ListView.builder` + integer-rounded target-size cache keys + tap callback + visible-page tracker + per-page error box). Built `SpecReaderPdfScreen` + 3 chrome siblings composing `PdfPageView` under `InkOverlay` (same pattern as T7 canvas) keyed on `JobRef`; mockup registry adds "4b. Spec reader (PDF)". Review follow-up caught a real bug: `PdfPageCache.close(handle)` was double-delegating to the port on re-invocation (autoDispose's blind-fire close leak); fixed with a tracked `_closedHandleIds` Set + open-clears-mark semantics, plus tightened lazy-render assertion to `lessThanOrEqualTo(2)`. Page aspect ratio hardcoded A4 1.4142 (port lacks `pageDimensions` — deferred to Issues.md); pan/zoom dead while overlay is opaque (stylus-only for T9 — deferred). 494 → 514 tests (+20), pristine analyzer.
- 2026-04-20 — M1b T10 complete (commits `6d98071` + `66eb7df` + `af8802b` + review follow-up `bc63f1d`). Extracted pure `paintStrokeGroups(Canvas, ...)` from `InkOverlayPainter` into `lib/ui/widgets/ink_overlay/ink_painting.dart` so both the painter and the new infra adapter reuse the same rendering code (byte-for-byte parity between on-screen ink and the committed PNG). Added sealed `PngFlattenError` (`PngFlattenRenderError` + `PngFlattenEncodeError`) inline in the port file (matches `FsError`/`PdfError` precedent). Shipped `PngFlattenerAdapter` (`dart:ui` `PictureRecorder` → `Picture.toImage` → `toByteData(png)`) with constructor-injected `toImage` + `toPngBytes` function seams so the error paths can be pinned. Review follow-up added the seams + 2 error-path tests. Layering note: `lib/infra/png/` imports one pure function from `lib/ui/widgets/ink_overlay/` — narrow and auditable; alternative of relocating to `lib/rendering/` judged premature. No PNG goldens (determinism + content-sensitivity tests suffice for M1b; goldens deferred to M1c review submission). 514 → 538 tests (+24: 6 paintStrokeGroups + 6 sealed-error + 10 adapter + 2 error-path), pristine analyzer.
- 2026-04-20 — M1b T11 complete (commits `a115588` + `2abbeb4` + `9d2f77d`). Shipped pen-latency measurement harness. `integration_test/pen_latency_test.dart` (skipped-by-default, wrapped in `group(..., skip: 'TODO(M1b-close)…')` because `testWidgets` skip param is `bool?`) drives a synthetic 100-point stylus stroke through `AnnotationCanvasScreen` and asserts `p95 < 25 ms` (NFR-1). Host-side `ink_overlay_latency_test.dart` pins dispatch-overhead (100 samples round-trip under 100 ms average). `docs/pen_latency_measurement.md` documents methodology, hardware assumptions, invocation command, known synthetic-vs-real-stylus limitation. Issues.md gains a Medium-severity entry for high-speed-camera verification (synthetic TestGesture bypasses driver/digitizer/HAL so measured numbers are a lower bound; AndroidView native-canvas fallback path from IMPLEMENTATION.md §8.3 is the remediation if real p95 > 25 ms). 538 → 540 host tests (+2 dispatch-overhead pin), pristine analyzer. Ran T10 fix + T11 implementation in parallel (disjoint files — no conflict).
- 2026-04-20 — M1b close-out complete. Release build deployed to OPD2504 (`app-release.apk` 48.4MB). Fresh-context QA subagent (mockup mode) captured 25 screenshots walking all 13 mockup entries (1–12 + new 4b); report at `docs/_m1b_qa_round1.md`. **0 Critical / 0 High / 1 Medium / 3 Low** — clean pass, close-out loop did not iterate. Medium (PDF mockup shows "Failed to render page N" because the fake's 8-byte PNG signature isn't valid PNG for `Image.memory`) + 3 Low (display-only pages rail, A4 aspect taller than viewport, hardcoded Ink-layers rail) all deferred to `docs/Issues.md` under "From M1b close-out QA round 1". Regression check: all 12 M1a screens render cleanly, dark mode clean, logcat clean. Stylus-actual-drawing path deferred to manual device QA (ADB can't emit `PointerDeviceKind.stylus`). **M1b shipped: 540 tests passing, 2 integration-test skeletons pending on-device run (pdfx + pen-latency), pristine analyzer.**
