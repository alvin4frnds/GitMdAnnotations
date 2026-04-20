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

### Issue: Git integration tests are platform-tagged skeletons
- **Severity:** Medium
- **Source:** M1a T10 (2026-04-20)
- **Screen/area:** `integration_test/infra/git/`, `lib/infra/git/_git_isolate.dart`.
- **Detail:** Integration tests for GitAdapter compile but are all `skip: 'TODO: ...'`. `cloneOrOpen` hard-codes `https://github.com/<owner>/<name>.git` so no local bare-repo harness can exercise it.
- **Proposed fix:** Add a `@visibleForTesting` `remoteUrlOverride` on `GitAdapter` (or equivalent seam) so integration tests can point at a `file://` bare repo; unskip the suite once it runs green against the connected tablet.

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
