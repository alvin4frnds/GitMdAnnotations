# Plan: Finish Phase 1 of GitMdAnnotations (Milestones 1c + 1d + gaps)

## Context

This side project — a pen-driven spec-review Android tablet app backed by git — has been running for several milestones. M1a (OAuth, job list, markdown read) and M1b (pen canvas, SVG, PDF render) are closed. M1c (review submission, Sync Up, conflicts) is ~90% code-complete but has unbuilt navigation wiring, two High-severity git adapter bugs, and a deferred RepoPicker that blocks on-device use. M1d (polish + NFRs) is entirely pending. A large latent defect — `libgit2dart` has no Android plugin and the APK ships zero `libgit2.so` — was surfaced during emulator verification earlier this session and partially fixed (x86_64 only, no HTTPS).

The user wants Phase 1 finished in one sustained push, using parallel Claude agents where safe but not at the cost of code quality. Memory note on their cadence: commit after every logical change; user handles all pushes; milestone QA is ADB-driven on the OPD2504 tablet with a separate triage agent.

**Execution step 0 — materialize this plan at `docs/implementation-plan2.md`** (plan mode blocks me from that write right now; it's the first action post-approval so the work stream lives with the repo and survives future fresh-context sessions).

## Work streams — ordered, with acceptance criteria

### Wave 1 — Foundations (run in parallel, agent-friendly)

Each item below is self-contained enough to delegate; no file-level conflict between them.

#### 1.1 — Bundle Inter + JetBrains Mono fonts  _[~1 hr, do myself]_
Closes `Issues.md:21-26`. Fixes the squiggly-underline glyphs and the `· —` monospace artifacts visible in every QA screenshot.
- Add `.ttf` files under `assets/fonts/`.
- Declare in `pubspec.yaml` under `flutter.fonts:`.
- Wire through `lib/ui/theme/app_theme.dart` + `appMono()` in `lib/ui/theme/tokens.dart` (or wherever `appMono` is defined — grep to confirm).
- Add a widget test pinning that theme resolves the expected family.
- **Accept:** emulator screencap shows clean monospace, no yellow underlines, `·` separator + `—` badge render as proper glyphs.

#### 1.2 — Update `docs/PROGRESS.md` (stale since 2026-04-20)  _[30 min, do myself]_
- Add M1c task board (T1–T7 + close-out status) mirroring the M1b table format.
- Add M1d task board (ChangelogViewer, Export backups, Recovery, NFR-2 tuning, NFR-8 profiling).
- Current-state block flipped to "M1c in progress".
- Reference commits (git log is authoritative; this doc is the readable overview).

#### 1.3 — Cross-compile libgit2 for `arm64-v8a` + `armeabi-v7a`  _[~30 min, do myself]_
Same CMake recipe as the x86_64 build already in `C:/Users/Praveen/Desktop/Code/Personal/libgit2-build/libgit2-1.5.0/`. Change `-DANDROID_ABI=arm64-v8a` (and again for armeabi-v7a). Drop outputs into `C:/Users/Praveen/Desktop/Code/Personal/libgit2dart-fork/android/src/main/jniLibs/<abi>/libgit2.so`.
- **Accept:** `aapt list app-debug.apk` shows `libgit2.so` under `lib/arm64-v8a/`, `lib/armeabi-v7a/`, and `lib/x86_64/`.

#### 1.4 — Push-error classification from substring match → structured  _[~2 hrs, delegate]_
Closes `Issues.md:65-70` (M1a-T10 deferred). Touches only `lib/infra/git/_git_isolate_helpers.dart` (`mapPushError`) + its test. Self-contained, ideal for an agent.
- **Accept:** unit tests exercise each documented libgit2 error class without substring heuristics.

### Wave 2 — Git stack Android-complete (sequential within stream, can run alongside Wave 3 start)

#### 2.1 — Build OpenSSL for Android (x86_64, arm64-v8a, armeabi-v7a)  _[~4 hrs, do myself]_
Blocks real sync against github.com. OpenSSL 3.x cross-compile via NDK `android.toolchain.cmake`. ~1 hr per ABI first time; can parallelize the three ABI builds via separate cmake build dirs.
- **Accept:** three `libssl.so` + `libcrypto.so` per-ABI outputs ready for linking.

#### 2.2 — Rebuild libgit2 with `-DUSE_HTTPS=OpenSSL`  _[~1 hr, do myself]_
Re-configure and rebuild libgit2 linking against the OpenSSL outputs from 2.1. Replace the `USE_HTTPS=OFF` binaries in the fork's jniLibs dirs.
- **Accept:** `Libgit2.features` on emulator now contains `GitFeature.https`. Extend `integration_test/libgit2_android_load_test.dart` with a `features.contains(GitFeature.https)` assertion.

#### 2.3 — Publish libgit2dart fork as git repo  _[~30 min, do myself]_
Makes the workspace self-contained — anyone cloning `GitMdAnnotations` resolves the fork without needing the sibling directory.
- Option A: GitHub repo under your account (public or private with deploy key).
- Option B: A `_vendor/libgit2dart/` submodule in this repo if private-ing is preferred.
- Swap `path: ../libgit2dart-fork` → `git: { url, ref: <pinned-sha> }` in `pubspec.yaml`.
- **Accept:** fresh `fvm flutter pub get` from a clean clone resolves without the sibling dir.

#### 2.4 — Close Issues.md "discontinued on pub.dev" entry  _[~10 min, do myself]_
With the fork live, "we are the maintainer" — strike through the Medium entry with a closing note, same pattern as the already-closed "Git integration tests are platform-tagged skeletons" entry.

#### 2.5 — Smoke-test the libgit2 stack on real OPD2504 tablet  _[~15 min, do myself]_
Reconnect the tablet, install APK, run `integration_test/libgit2_android_load_test.dart -d NBB6BMB6QGQWLFV4`. Validates arm64-v8a .so actually works on hardware, not just emulator.

### Wave 3 — RepoPicker (blocks real-device E2E; can start during Wave 2)

#### 3.1 — RepoPicker screen + controller + provider  _[~6 hrs, do myself]_
Closes the deferred M1a item referenced in `lib/bootstrap.dart:57` + `lib/app/providers/spec_providers.dart:35,37`. Key references:
- `RepoRef` entity at `lib/domain/entities/repo_ref.dart`.
- `currentRepoProvider` + `currentWorkdirProvider` at `lib/app/providers/spec_providers.dart:22,37` — set these.
- `GitAdapter.cloneOrOpen` at `lib/infra/git/_git_isolate.dart` — invoked on first pick.
- Auth session available via `authControllerProvider` → reuse the token for GitHub API repo listing.

Scope:
- UI: new route between SignIn success and JobList (insert into `_AuthGate` at `lib/main.dart:48-54`).
- List authenticated user's repos via GitHub API (`dio` is already a dep; new `GitHubReposPort` if we want clean layering).
- On pick: compute local workdir (`getApplicationDocumentsDirectory()/repos/<owner>/<name>`), clone if absent, set the two providers, navigate to JobList.
- Empty / error / no-network states.
- Retire `DEV_SEED_ENABLED` hatch (or keep it as a dev shortcut — pick one).
- **Accept:** clean-install boot → sign in → repo picker lists real repos → picking one clones it and lands on JobList with real jobs.

#### 3.2 — Fix High `Issues.md`: claude-jobs branch bootstrap  _[~3 hrs, do myself]_
`lib/infra/git/_git_isolate.dart:_handleCloneOrOpen` — after `git2.Repository.clone`, if `refs/remotes/origin/claude-jobs` exists, create `refs/heads/claude-jobs` pointing at the same Oid. Covers Sync Down and RepoPicker's first-clone path.
- **Accept:** `integration_test/infra/git/git_adapter_test.dart` unskips its relevant tests; RepoPicker's clone-from-existing-sidecar case works end-to-end.

#### 3.3 — Fix High `Issues.md`: resetHard('origin/claude-jobs') SHA-only  _[~1 hr, do myself]_
`_handleResetHard`: resolve non-hex refs via `Revparse.single(repo: repo, spec: req.ref).oid` before falling back to `Oid.fromSHA`.
- **Accept:** `integration_test/sync_conflict_test.dart` runs green on-device (not just host VM).

### Wave 4 — M1c close-out (depends on Wave 3 for navigation to matter)

#### 4.1 — JobList → SpecReader navigation  _[~2 hrs, do myself]_
`lib/ui/screens/job_list/job_list_screen.dart:530` — wire `_JobRow.onTap` to `Navigator.push` the appropriate SpecReader (Md or Pdf) based on `Job.sourceKind`. Pass `JobRef` through.

#### 4.2 — SpecReader → AnnotationCanvas + ReviewPanel  _[~2 hrs, do myself]_
`lib/ui/screens/spec_reader_md/spec_reader_md_screen.dart:67,70` — wire "Review panel →" to `ReviewPanelScreen` and Submit through the already-landed M1c-T7 orchestrator. Make a mobile-ergonomic path to AnnotationCanvas (e.g., "Annotate" button in the pen-tool bar pushes `AnnotationCanvasScreen(jobRef: widget.jobRef)`).
- **Accept:** full path JobList → SpecReader → Canvas (annotate) → ReviewPanel (type questions) → Submit → commits land on `claude-jobs` branch.

#### 4.3 — Review draft auto-save timer  _[~3 hrs, delegate candidate]_
`lib/app/controllers/review_controller.dart` area. A `Timer.periodic` that writes the draft to disk every N seconds; restores on reopen. Well-scoped for an agent if the existing `review_draft_store.dart` sibling (from commit `8df5fb8`) exposes the right seam.
- **Accept:** widget test + unit test covering save-on-timer + restore-on-reopen.

#### 4.4 — M1c close-out QA round  _[~4 hrs, do myself]_
Build release APK, install on tablet (now with real libgit2 from Wave 2), drive full golden path via ADB per the standing memory loop, capture screenshots, triage findings. `docs/_m1c_qa_round1*` (already locally untracked) may have scaffolding — reuse or supersede.
- **Accept:** no Critical / High findings; Medium/Low to Issues.md; PROGRESS.md closes M1c.

### Wave 5 — M1d (runs after M1c closes; streams inside can parallelize)

#### 5.1 — ChangelogViewer  _[~5 hrs, delegate]_
Parse `## Changelog` across all jobs, render timeline. Isolated new feature with clear contract. Good agent task.

#### 5.2 — Settings / Export backups (SAF)  _[~4 hrs, delegate]_
Storage Access Framework integration. `path_provider` is already a dep; this is Android-platform-channel work. Isolated.

#### 5.3 — Recovery flows  _[~5 hrs, do myself]_
Corrupted `.git` surfacing + expired-token re-auth polish. Touches auth controller + git adapter error paths. Enough cross-cutting that I want control.

#### 5.4 — Cold-start NFR-2 tuning  _[~3 hrs, do myself]_
Preload last-opened job metadata. `main.dart` + `auth_controller.dart` + `JobListController.build` area.

#### 5.5 — Battery profiling NFR-8  _[~1 hr active + 4 hr measurement, do myself]_
Automation harness kicks off 4-hour continuous-review loop; dump battery at intervals via `adb shell dumpsys batterystats`.

### Wave 6 — NFR verification + final polish

- **NFR-1** real-stylus p95 latency on OPD2504 (complete the synthetic → real measurement the M1b-T11 harness deferred).
- **NFR-7** TalkBack accessibility pass across markdown reading.
- **NFR-9** storage LRU eviction test with >1 GB cached.
- **NFR-10** on-device sync timing against a realistic ~5 MB job.
- Any leftover Issues.md entries (SyncController clock injection, dark-mode re-audit, "just arrived" treatment, M1b PDF mockup defect).

## Parallelization map

Shown left to right roughly in time; same column = concurrent.

```
Wave 1:  [1.1 fonts]  [1.2 PROGRESS]  [1.3 libgit2 arm]  [1.4 push-errors*]
                                                          ↓
Wave 2:  [2.1 openssl] → [2.2 relink] → [2.3 fork git] → [2.4 close]
                                         [2.5 tablet smoke]
Wave 3:  [3.1 RepoPicker*]  [3.2 cloneOrOpen fix]  [3.3 resetHard fix]
Wave 4:  [4.1 nav]  [4.2 reader→panel]  [4.3 auto-save*]
         [4.4 QA]
Wave 5:  [5.1 ChangelogViewer*]  [5.2 Export*]  [5.3 Recovery]  [5.4 NFR-2]  [5.5 battery]
Wave 6:  [NFR-1, 7, 9, 10 + leftover polish]
```

`*` = tasks I'll delegate to a parallel agent (self-contained enough to not conflict). Other tasks touch adapters / core widgets / composition root and I'll do myself to keep tests coherent.

## Verification strategy

- **After each commit:** `fvm flutter test test/` green (current baseline: 621/+2-pre-existing). Delta to this number is part of the commit message.
- **After each Wave:** `fvm flutter analyze` clean + rebuild APK + emulator smoke.
- **Gates for M1c close (end Wave 4):** all M1c integration tests pass on emulator + real tablet; ADB QA walkthrough finds no Critical/High.
- **Gates for Phase 1 close (end Wave 6):** every NFR in §7 has a pinned measurement on OPD2504; Issues.md has no open High severity entries; PROGRESS.md reflects Phase 1 closed.

## Files / references the execution will touch (catalog)

- **Theme / fonts:** `pubspec.yaml`, `lib/ui/theme/app_theme.dart`, `lib/ui/theme/tokens.dart`, `assets/fonts/*.ttf`.
- **libgit2 fork:** `C:/Users/Praveen/Desktop/Code/Personal/libgit2dart-fork/` (outside repo) + `C:/Users/Praveen/Desktop/Code/Personal/libgit2-build/` (build artifacts).
- **Git adapter fixes:** `lib/infra/git/_git_isolate.dart` (`_handleCloneOrOpen`, `_handleResetHard`), `lib/infra/git/_git_isolate_helpers.dart`.
- **RepoPicker:** new `lib/ui/screens/repo_picker/`, new `lib/app/controllers/repo_picker_controller.dart`, possibly a new `lib/domain/ports/github_repos_port.dart` + `lib/infra/github/` adapter. Hook into `lib/main.dart:_AuthGate` + `lib/app/providers/spec_providers.dart`.
- **Navigation wiring:** `lib/ui/screens/job_list/job_list_screen.dart:530`, `lib/ui/screens/spec_reader_md/spec_reader_md_screen.dart:67,70`, `lib/ui/screens/spec_reader_pdf/*`.
- **Review auto-save:** `lib/app/controllers/review_controller.dart`, `lib/app/controllers/review_draft_store.dart`.
- **M1d:** new `lib/ui/screens/changelog_viewer/`, new `lib/ui/screens/settings/`, existing `lib/app/controllers/auth_controller.dart` (recovery polish), `lib/main.dart` (cold-start preload).
- **Docs:** `docs/PROGRESS.md`, `docs/Issues.md`, new `docs/implementation-plan2.md`.

## Risks + bail-out protocol

- **OpenSSL cross-compile complications.** If 2.1 slips past ~6 hrs, fall back to mbedTLS (smaller, embedded-first, simpler build). Both are supported by libgit2's `USE_HTTPS` flag.
- **GitHub API rate limits during RepoPicker dev.** Cache responses locally during iteration; don't burn quota in a hot loop.
- **Tablet + emulator contention.** Both appear in `adb devices` when tablet is plugged in. Always use `-s <device-id>` explicitly; never run a deploy unqualified.
- **Agent conflicts.** If two agents end up modifying overlapping files despite the wave partitioning above, I stop the second, merge by hand, and narrow the task boundary.
- **Time budget.** My estimate was 60–90 engineering hours for Phase 1 completion. Agents help but do not collapse this to one session. I will commit frequently and narrate progress; if we hit a natural wall (e.g., 4-hour battery measurement) I surface it and either proceed in background or park for the next session.

## Exit from plan mode — immediate actions

1. Materialize this plan verbatim at `docs/implementation-plan2.md` (user-requested location).
2. Begin Wave 1: launch delegate agent for 1.4 (push-error classification) in background; start 1.1 (fonts) myself in parallel with 1.3 (libgit2 arm builds).
3. Commit each sub-task as it lands.
