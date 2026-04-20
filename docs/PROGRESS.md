# Implementation Progress

Live tracker for Milestones 1a–1d of [IMPLEMENTATION.md](IMPLEMENTATION.md). Updated at the end of every milestone. The commit history is the authoritative source; this doc is the readable overview.

- Status legend: ✅ done · 🟡 in progress · ⏳ pending · ⛔ blocked

## Current state

**Milestone:** 1a — OAuth, repo picker, `claude-jobs` bootstrap, Sync Down, markdown read-only, offline cache.
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

### Milestones 1b–1d

See IMPLEMENTATION.md §6.2–6.4. Expanded task boards will appear here as each milestone starts.

## Change log

- 2026-04-20 — UI spike deployed; 12 screens rendering on OPD2504. PROGRESS.md initialized. Milestone 1a started.
