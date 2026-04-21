# Issues Ledger

Deferred findings from milestone QA rounds. Critical + High items are fixed before milestone close-out; Medium and Low accumulate here for the next scheduled polish pass or for opportunistic fixes during related work.

## From M1a QA (2026-04-20)

### Issue: Job list first-row "just arrived" treatment missing
- **Severity:** Medium
- **Source:** M1a QA (2026-04-20)
- **Screen/area:** Job list (`lib/ui/screens/job_list/…`)
- **Detail:** Pre-wiring, the topmost job row had `accentSoftBg` background, 4px left accent border, and a "just arrived" inline label. After wiring through `JobListController` the treatment was dropped because `Job` carries no sync-arrival timestamp. Fixed = first row (or rows synced within the last N minutes) visually differentiated again.
- **Proposed fix:** Add an `arrivedAt` / `isFreshlySynced` field to `Job` (or compute from `SyncRun` metadata), thread it through `JobListController`, and re-apply the accent treatment in the row builder.

### Issue: Re-audit dark mode after M1a close-out
- **Severity:** Medium
- **Source:** M1a QA (2026-04-20)
- **Screen/area:** All screens, mockup browser theme toggle.
- **Detail:** QA pass only covered light mode; dark-mode walkthrough was not captured. Fixed = full 12-screen dark-mode screenshot set reviewed with no regressions against the UI spike.
- **Proposed fix:** Re-run the automated QA screenshot agent with the theme toggle flipped and triage any new findings.

### Issue: Inter font not bundled; typography falls back to Roboto
- **Severity:** Medium
- **Source:** M1a QA (2026-04-20)
- **Screen/area:** Global (all screens).
- **Detail:** `appMono` / body text currently resolves to system Roboto because Inter `.ttf` files aren't declared in `pubspec.yaml` assets. Fixed = Inter and the mono variant bundled and surfaced via the theme, matching UI spike.
- **Proposed fix:** Add Inter Regular/Medium/SemiBold/Bold + Inter Mono (or JetBrains Mono) under `fonts:` in `pubspec.yaml`, wire them into `app_theme.dart` and `appMono()`.

### Issue: Real OAuth flow unverified; `_prodClientId` is placeholder
- **Severity:** Medium
- **Source:** M1a QA (2026-04-20)
- **Screen/area:** `lib/bootstrap.dart` (`_prodClientId`), real-mode sign-in path.
- **Detail:** `APP_MODE=real` can't be exercised because `_prodClientId = 'OVERRIDE_ME'`. Fixed = registered GitHub OAuth App, client id wired in, one end-to-end sign-in verified on-device.
- **Proposed fix:** Register the OAuth App, replace `_prodClientId`, and add a manual smoke-test checklist entry to `docs/PROGRESS.md`.

### Issue: libgit2dart is discontinued on pub.dev
- **Severity:** Medium
- **Source:** M1a T10 (2026-04-20)
- **Screen/area:** `lib/infra/git/` git adapter chain.
- **Detail:** `libgit2dart 1.2.2` works today but is marked `discontinued`. No active maintainer. Fixed = migration plan or fork before the library breaks against a future Flutter / Dart SDK.
- **Proposed fix:** Spike-evaluate `git2dart`, shelling to `git` via `Process`, or forking + vendoring `libgit2dart`. Decide in a dedicated follow-up task.

### ~~Issue: Git integration tests are platform-tagged skeletons~~ — Closed in M1c-T6 (`c4bc604`)
- ~~**Severity:** Medium~~
- ~~**Source:** M1a T10 (2026-04-20)~~
- ~~**Screen/area:** `integration_test/infra/git/`, `lib/infra/git/_git_isolate.dart`.~~
- ~~**Detail:** Integration tests for GitAdapter compile but are all `skip: 'TODO: ...'`. `cloneOrOpen` hard-codes `https://github.com/<owner>/<name>.git` so no local bare-repo harness can exercise it.~~
- ~~**Proposed fix:** Add a `@visibleForTesting` `remoteUrlOverride` on `GitAdapter` (or equivalent seam) so integration tests can point at a `file://` bare repo; unskip the suite once it runs green against the connected tablet.~~
- **Closed in M1c-T6 (`c4bc604`):** `GitAdapter.withRemoteUrlOverride` constructor seam landed and is exercised end-to-end by `integration_test/sync_conflict_test.dart` (Sync Up happy + diverged conflict). The four still-skipped tests under `integration_test/infra/git/git_adapter_test.dart` are now tracked as their own follow-ups alongside the `_handleResetHard` + `claude-jobs` bootstrap entries below — the seam gap this issue flagged is closed.

### Issue: claude-jobs bootstrap from origin/claude-jobs not created by GitAdapter.cloneOrOpen
- **Severity:** Medium
- **Source:** M1c T6 (2026-04-21)
- **Screen/area:** `lib/infra/git/_git_isolate.dart` (`_handleCloneOrOpen`), `lib/domain/services/sync_service.dart`.
- **Detail:** `_handleCloneOrOpen` passes `checkoutBranch: repo.defaultBranch` to `git2.Repository.clone`, producing only `refs/heads/main`. The first `adapter.commit(..., branch: 'claude-jobs')` then fails inside `checkoutBranch()` because `refs/heads/claude-jobs` doesn't exist locally — only `refs/remotes/origin/claude-jobs` does. `integration_test/sync_conflict_test.dart` works around this by bootstrapping the local branch via a direct libgit2 call before calling the adapter.
- **Cross-ref:** overlaps with the pre-existing "`claude-jobs` bootstrap from origin/main not yet implemented" entry (M1a T11). That one covers Sync Down's `SyncService.syncDown` bootstrap; this one covers `GitAdapter.cloneOrOpen` creating the sidecar branch locally when it already exists on origin.
- **Proposed fix:** After `git2.Repository.clone` in `_handleCloneOrOpen`, if `refs/remotes/origin/claude-jobs` exists, create `refs/heads/claude-jobs` pointing at the same Oid. When origin has no `claude-jobs` yet, the Sync Down bootstrap (pre-existing entry) handles the create-from-main path.

### Issue: ConflictResolver.archiveAndReset calls resetHard('origin/claude-jobs') but GitAdapter.resetHard only accepts SHAs
- **Severity:** High (for real sync) — blocks the remote-wins conflict flow against a real git remote.
- **Source:** M1c T6 (2026-04-21)
- **Screen/area:** `lib/infra/git/_git_isolate.dart` (`_handleResetHard`), `lib/domain/services/conflict_resolver.dart`.
- **Detail:** `_handleResetHard` calls `git2.Oid.fromSHA(repo: repo, sha: req.ref)`, which throws `ArgumentError('<ref> is not a valid sha hex string')` for anything that isn't a 7–40-char hex string. `ConflictResolver.archiveAndReset` passes the string `'origin/claude-jobs'` (a ref name, not a SHA). Only `FakeGitPort.resetHard` currently accepts a ref-name string (by looking it up in its snapshot map). Against the real adapter, the conflict-path Sync Up will always throw `ArgumentError` after backup, instead of resetting. The T6 integration test will surface this on the connected tablet.
- **Proposed fix:** In `_handleResetHard`, if `req.ref` is not hex (or equivalently: resolve via `Revparse.single(repo: repo, spec: req.ref).oid` first, fall back to `Oid.fromSHA` for raw SHAs). Alternatively, promote the resolution up into `ConflictResolver` and pass already-resolved SHAs (cleaner domain semantics but costs a new port method to resolve `origin/<branch>`).

### Issue: libgit2dart has no Android plugin — APK ships zero `libgit2.so`; Sync/Submit will crash on device
- **Severity:** **High** — the entire on-device git path (Sync Down, Sync Up, Submit Review, Approve) will crash with a native-lib load error the first time anyone exercises it on the tablet. Blocks Phase 1 exit.
- **Source:** M1d emulator verification (2026-04-21) — surfaced while inspecting the APK during a broader emulator smoke test; confirmed by unpacking `build/app/outputs/flutter-apk/app-debug.apk`.
- **Screen/area:** `lib/infra/git/` adapter chain, `pubspec.yaml` (`libgit2dart ^1.2.2`), Android Gradle build output.
- **Detail:**
  - `libgit2dart 1.2.2` declares its Flutter plugin platforms as `linux`, `macos`, `windows` **only** — see `~/AppData/Local/Pub/Cache/hosted/pub.dev/libgit2dart-1.2.2/pubspec.yaml`. There is no `android/` directory in the package, no `pluginClass` for Android, no prebuilt `.so`.
  - `aapt list build/app/outputs/flutter-apk/app-debug.apk | grep ^lib/` returns **only** `libdartjni.so` + `libflutter.so` + `libVkLayer_khronos_validation.so` for every ABI (arm64-v8a, armeabi-v7a, x86_64). **No `libgit2.so`, no `libgit2dart_plugin.so`.**
  - At runtime, `libgit2dart/lib/src/util.dart` does `DynamicLibrary.open(_resolveLibPath(name) ?? name)`. With no bundled `.so`, the first call into any git operation throws.
  - **Why this has not been caught yet:**
    - M1a and M1b close-out QA ran in mockup mode with fakes seeded via `bootstrap.dart`; no real git path was reachable.
    - M1c-T6's integration test (`integration_test/sync_conflict_test.dart`) runs on the Windows/Linux host via `fvm flutter test`, which picks up the bundled Windows/Linux `.so` from the pub cache. It never validates on-device sync.
    - The UI buttons that would trigger `GitAdapter` (`Sync Down`, `Sync Up`, `New spec`, spec-row tap) are all `onPressed: () {}` / `onTap: () {}` placeholders at `lib/ui/screens/job_list/job_list_screen.dart:77,169,298,302,530`. The Submit path wired in M1c-T7 (`0cc6fb2`) is behind the JobList → SpecReader → Canvas → Review-Panel navigation gap and has never fired on a physical device.
    - `gitPortProvider` is a lazy factory (`overrideWith((ref) => GitAdapter(...))` at `lib/bootstrap.dart:51`); no eager instantiation means cold-start stays clean.
  - Overlaps with the pre-existing "libgit2dart is discontinued on pub.dev" entry above. Both resolve to the same remediation path — treat them as a single migration task.
- **Proposed fix:** Choose one, execute before wiring any real-device UI that reaches `GitAdapter`:
  1. **Fork + vendor libgit2dart with an Android NDK build recipe (recommended).** Add `android/CMakeLists.txt` mirroring the existing `linux/` recipe, using `$ANDROID_NDK_HOME`'s CMake toolchain for arm64-v8a / armeabi-v7a / x86_64. libgit2 itself builds cleanly for Android NDK — upstream CI covers it. Declare `pluginClass: Libgit2dartPlugin` under `platforms.android:` in the fork's `pubspec.yaml` and reference the fork as a git dep in our own `pubspec.yaml`. Preserves the existing `GitPort` / `GitAdapter` surface and keeps all M1c-T1–T6 tests green. Closes the "discontinued" entry at the same time — we're the maintainer now. Adds ~2–3 MB per ABI to the APK.
  2. **Ship a statically-linked `git` binary + shell via `dart:io Process`.** On Android 10+, `filesDir` is mounted no-exec; executables must live under `nativeLibraryDir`. Trick Gradle into packaging the `git` binary as `libgit.so` under `jniLibs/<abi>/`, then `Process.run` it. Adds ~15–20 MB to APK, requires cross-compiling git from source for three ABIs, and the GitPort implementation becomes a subprocess driver. More code, larger binary, but completely side-steps the libgit2 API.
  3. **Switch to a different Dart git library with Android support.** Survey: `git2dart` (another libgit2 FFI binding — check its Android story), `package:git` (pure Dart, but incomplete for our use), JGit via a Kotlin platform channel (heavy). Option (1) is likely less work than rewriting adapter code against a new library surface, but worth a half-day spike to verify.
- **Testing hook after fix:** add an on-device integration test (`integration_test/infra/git/git_android_load_test.dart`) that exercises `GitAdapter.cloneOrOpen` against a small file-URL bare repo and runs on `emulator-5554` or the tablet. Runs in CI as `fvm flutter test integration_test/... -d emulator-5554`. Without this, the next regression of the same shape will escape to production again.

### Issue: Push-error classification is heuristic string-matching
- **Severity:** Medium
- **Source:** M1a T10 (2026-04-20)
- **Screen/area:** `lib/infra/git/_git_isolate_helpers.dart` → `mapPushError`.
- **Detail:** `libgit2dart` exposes only `toString()` on `LibGit2Error`, so non-fast-forward and 401 failures are detected via substring matches ("non-fast-forward", "rejected", "401", "unauthorized"). Brittle once we observe real-world GitHub failures.
- **Proposed fix:** Log the raw `toString()` to a structured sink during M1c Sync Up integration, then harden the mapping table against the real messages we see.

### Issue: `SyncController` uses `DateTime.now()` directly; no clock injection
- **Severity:** Low
- **Source:** M1a T11 (2026-04-20)
- **Screen/area:** `lib/app/controllers/sync_controller.dart`.
- **Detail:** Will matter once we add sync-timing telemetry (M1d or later). Right now it only affects `SyncDone(at)` on the happy path.
- **Proposed fix:** Introduce a `ClockPort` in `lib/domain/ports/` + a `SystemClock` adapter; override in tests via Riverpod, wire at composition root.

### Issue: `claude-jobs` bootstrap from origin/main not yet implemented
- **Severity:** Low
- **Source:** M1a T11 (2026-04-20)
- **Screen/area:** `lib/domain/services/sync_service.dart`.
- **Detail:** When local `claude-jobs` is missing, `SyncService.syncDown` currently skips the merge. PRD requires creating it from `origin/main` and pushing. Explicitly deferred to M1c.
- **Proposed fix:** Extend `SyncService.syncDown` in M1c with a "`claude-jobs` bootstrap" branch that clones from `origin/main` and pushes before the first merge step.

### Issue: RepoPicker screen not implemented
- **Severity:** Low (scope)
- **Source:** M1a T12 (2026-04-20)
- **Screen/area:** UI.
- **Detail:** `currentRepoProvider` + `currentWorkdirProvider` are installed but real-mode starts with both `null`. The only way to set them right now is via the M1a bootstrap fixtures.
- **Proposed fix:** Ship RepoPicker in M1c per the plan in IMPLEMENTATION.md §6.3.

### Issue: File-kind chip styling nit (.md vs .pdf)
- **Severity:** Low
- **Source:** M1a QA (2026-04-20)
- **Screen/area:** Job list file-kind chip.
- **Detail:** Chip is currently neutral for all file kinds; would benefit from a subtle accent for `.md` vs `.pdf` so reviewers can scan the list at a glance.
- **Proposed fix:** Map chip background/foreground by `FileKind` in the row builder; use existing accent tokens.

### Issue: Auth state doesn't reset after navigating away from Sign In
- **Severity:** Low
- **Source:** M1a QA (2026-04-20)
- **Screen/area:** Sign In + mockup browser shell.
- **Detail:** After opening Sign In, navigating away, and relaunching, the device-code panel persists rather than returning to `AuthSignedOut`. Plausible (auth state is process-global) but recovery UX should be explicit.
- **Proposed fix:** Confirm in M1b whether to auto-cancel the in-flight device flow on screen-pop, or surface a "Cancel and restart" affordance in the awaiting-user panel.

### Issue: Email-null fallback from GitHub not implemented
- **Severity:** Low
- **Source:** M1a T6 (2026-04-20)
- **Screen/area:** `lib/infra/auth/github_oauth_adapter.dart`.
- **Detail:** When a user has "Keep my email address private" enabled, `GET /user` returns `email: null`. We currently record `email: ''`, so commits carry an empty email.
- **Proposed fix:** Fallback to `GET /user/emails` when `/user` returns null email; pick the primary verified address.

## From M1b T9 (2026-04-20)

### Issue: PDF page aspect ratio hardcoded (A4 portrait, 1.4142)
- **Severity:** Medium
- **Source:** M1b T9 (2026-04-20)
- **Screen/area:** `lib/ui/widgets/pdf_page_view/pdf_page_view.dart`, `lib/domain/ports/pdf_raster_port.dart`.
- **Detail:** `PdfPageView` sizes every page tile as `width * 1.4142` (A4 portrait). Pages that are letter, tabloid, landscape, or mixed-orientation render with whitespace or clipping. The `PdfRasterPort` has no `pageDimensions(pageNumber)` getter yet — adding one is a T8 follow-up.
- **Proposed fix:** Extend `PdfRasterPort` with `Future<PdfPageDimensions> pageDimensions(handle, pageNumber)`; add a family provider `pdfPageDimensionsProvider` so `PdfPageView` can size each tile correctly. Wire through `PdfxAdapter` (exposes `page.width`/`page.height` via `pdfx.PdfPage`) and `FakePdfRasterPort` (register per-page dims).

### Issue: Pan/zoom disabled while InkOverlay covers the PDF
- **Severity:** Medium
- **Source:** M1b T9 (2026-04-20)
- **Screen/area:** `lib/ui/screens/spec_reader_pdf/spec_reader_pdf_pane.dart`.
- **Detail:** `InkOverlay` uses `HitTestBehavior.opaque` so touch pan/zoom (that would otherwise drive the underlying `InteractiveViewer`) is swallowed. T9 accepts this tradeoff (stylus-only) because the session drops non-stylus pointer events anyway. Result: users can't pinch-zoom or scroll the PDF while the pen-annotation overlay is mounted.
- **Proposed fix:** Add a pen/pan toggle in the top chrome (mockup already sketches a read/pen tool switch). When "pan" is active, switch the overlay to `HitTestBehavior.translucent` and forward non-stylus events to the `InteractiveViewer`; when "pen" is active, keep the current opaque behaviour.

### Issue: PDF anchor derivation is a sentinel placeholder
- **Severity:** Medium
- **Source:** M1b T9 (2026-04-20)
- **Screen/area:** `lib/ui/screens/spec_reader_pdf/spec_reader_pdf_screen.dart` — `_placeholderAnchor()`.
- **Detail:** Every stroke gets `PdfAnchor(page: <visiblePage>, bbox: (0,0,0,0), sourceSha: '')`. Real bbox derivation from `(page, localOffset)` requires knowing the current scroll offset + the page-tile's position + the PDF-page coordinate transform. Deferred to a dedicated anchor-derivation task per IMPLEMENTATION.md §4.4 `anchor_for(page, bbox)`.
- **Proposed fix:** Extract `PdfAnchorResolver` from the screen into `lib/domain/services/`; it should accept `(page, localOffsetInPage, pageDims, sourceSha)` and emit a `PdfAnchor` with the stroke's bbox in PDF-page coordinates. The screen derives `localOffsetInPage` from the `GestureDetector` in `PdfPageTile` and pipes it into the controller.

## From M1b T8 review (2026-04-20)

### Issue: PdfxAdapter native-path coverage deferred to on-device run
- **Severity:** Medium
- **Source:** M1b T8 review (2026-04-20)
- **Screen/area:** `lib/infra/pdf/pdfx_adapter.dart`, `integration_test/infra/pdf/pdfx_adapter_test.dart`, `test/infra/pdf/pdfx_adapter_test.dart`.
- **Detail:** `pdfx` is a platform-channel plugin; under `flutter test` on the host VM every real `open`/`renderPage` call raises `MissingPluginException(No implementation found for method open.document.file on channel io.scer.pdf_renderer)` because no Flutter engine is attached. The T8 review follow-up added four host-side tests that exercise only the pre-native branches (bad-path → `PdfOpenError` wrap, unknown-handle `close` idempotency). The remaining contract points — `pageCount` + `pdf-doc-<...>` id shape on a successful open, PNG-signature bytes from `renderPage`, `RangeError` on `pageNumber` out of bounds, finally-close of the pdfx page object, after-close `renderPage` behaviour — still live in `integration_test/infra/pdf/pdfx_adapter_test.dart` as `skip:`ped skeletons.
- **Proposed fix:** On M1b close-out, run `fvm flutter test integration_test/infra/pdf/pdfx_adapter_test.dart -d <OPD2504-id>`: unskip the three tests, wire the rootBundle asset through a tempfile so `openFile` can consume a real path, and pin the PNG-signature + range-error + id-shape assertions enumerated in the T8 fix-subagent brief.

## From M1b close-out QA round 1 (2026-04-20)

Reference: `docs/_m1b_qa_round1.md` + 25 screenshots in `docs/_m1b_qa_round1/`. 0 Critical / 0 High / 1 Medium / 3 Low. Clean pass — close-out loop did not iterate.

### Issue: PDF mockup pages render "Failed to render page N" instead of transparent placeholders
- **Severity:** Medium
- **Source:** M1b close-out QA round 1 (2026-04-20)
- **Screen/area:** `lib/ui/widgets/pdf_page_view/pdf_page_tile.dart:48,70-80`; `lib/domain/fakes/fake_pdf_raster_port.dart:108-109`; mockup seeding in `lib/bootstrap.dart` (`_mockupOverrides` `FakePdfRasterPort.register` call).
- **Detail:** `FakePdfRasterPort` returns the 8-byte PNG magic signature for unregistered pages. Those 8 bytes are not a decodable PNG (no IHDR/IDAT/IEND), so `Image.memory`'s `errorBuilder` fires and `_ErrorBox` renders a red-tinted "Failed to render page N" card. Dominant visual on screen 4b in both light and dark modes — a mockup visitor reasonably reads it as broken rather than "placeholder". No crash; no regression vs. M1a (screen is new to M1b).
- **Proposed fix:** Either (a) seed `pagePngs:` in bootstrap with a tiny valid 1×1 transparent PNG for each of the 3 mockup pages, or (b) silence the error box in `PdfPageTile` when the bytes are the signature-only sentinel (cheapest: check `bytes.length == 8` before rendering `_ErrorBox`). Option (a) is more faithful; option (b) avoids touching bootstrap.

### Issue: PDF Pages rail is display-only (no jump-scroll on tap)
- **Severity:** Low
- **Source:** M1b close-out QA round 1 (2026-04-20)
- **Screen/area:** `lib/ui/screens/spec_reader_pdf/spec_reader_pdf_rail.dart`.
- **Detail:** Tapping "Page 2" / "Page 3" in the rail does nothing. Rail comment acknowledges this is intentional for M1b, but the visual affordance reads as clickable.
- **Proposed fix:** Wire `ScrollController.animateTo(pageOffset)` on tap. Reuse the controller already held by `PdfPageView`'s visible-page tracker; expose via callback.

### Issue: PDF aspect ratio 1.4142 produces tiles taller than viewport on 2800×1980
- **Severity:** Low
- **Source:** M1b close-out QA round 1 (2026-04-20)
- **Screen/area:** `lib/ui/widgets/pdf_page_view/pdf_page_view.dart` — `pageAspectRatio` default.
- **Detail:** A4-portrait tiles are ~1860w × ~2630h logical — taller than the ~1860px visible height after rails. Only the top of page 1 appears. Combined with the pan/zoom-blocked T9 Issues.md entry, page content effectively can't be explored in mockup.
- **Proposed fix:** Shrink the default aspect when no per-page dims are known (e.g. 1.0 square), or add a page indicator chip to the chrome.

### Issue: Annotation canvas "Ink layers" rail hardcoded to Groups A/B/C
- **Severity:** Low
- **Source:** M1b close-out QA round 1 (2026-04-20)
- **Screen/area:** `lib/ui/screens/annotation_canvas/left_rail.dart`.
- **Detail:** Rail shows `Group A — line 47 / B — line 23 / C — line 89` regardless of the controller's actual `state.groups`. Commented as display-only chrome but visually reads as state.
- **Proposed fix:** `ref.watch(annotationControllerProvider(jobRef)).groups` into the rail; map each committed group to `Group <letter> — line <anchor.lineNumber>` (or page/bbox for PDF anchors). Empty-state = rail message rather than A/B/C chrome.

## From M1b T11 (2026-04-20)

### Issue: Real-stylus pen-latency gap requires camera observation
- **Severity:** Medium
- **Source:** M1b T11 (2026-04-20)
- **Screen/area:** `integration_test/pen_latency_test.dart`, `docs/pen_latency_measurement.md`.
- **Detail:** The T11 NFR-1 harness uses `flutter_test`'s `TestGesture` to synthesize `PointerEvent`s directly into the Flutter binding. This bypasses the stylus driver, the digitizer sampling loop, the HAL queue, and any compositor buffering above Flutter's engine. The measured p50/p95/p99 therefore reflect only Flutter's paint pipeline and are a **lower bound** on real-world ink latency. NFR-1 (<25 ms p95) is a user-perceived-latency gate; the real-world delta vs. our synthetic numbers is currently unknown.
- **Proposed fix:** Post-M1b, add a manual high-speed-camera measurement step to the close-out protocol: record stylus tip + screen at ≥240 fps, count frames from contact to first ink paint, cross-reference against the synthetic p95. If the camera-observed p95 exceeds 25 ms while the synthetic number sits comfortably under, pursue the IMPLEMENTATION.md §8.3 fallback — embed a native Android canvas view via `AndroidView` — since the delta would be sitting below Flutter. Tools: a smartphone high-speed mode (iPhone 240 fps / modern Android equivalents) is sufficient; a dedicated pro camera is overkill for a single-number gate.
