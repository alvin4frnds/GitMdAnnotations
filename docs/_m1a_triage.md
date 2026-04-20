# M1a Triage — 2026-04-20

Fresh-context triage of `docs/_m1a_qa_report.md`. Source of truth: QA report + `bootstrap.dart`, `fake_auth_port.dart`, `sign_in_screen.dart`, `auth_controller.dart`.

## 1. Summary table

| # | Finding | QA Severity | Triage decision |
|---|---------|-------------|-----------------|
| 1 | PAT dialog opens into fully black surface | Critical | **Fix now** — blocks the documented auth fallback. |
| 2 | Device-code panel renders without a code | High | **Fix now** — mockup mode's primary auth path is unverifiable without this. |
| 3 | "Just arrived" visual treatment dropped on first job row | Medium | Defer to Issues.md — requires new metadata on `Job`; out of scope for M1a close-out. |
| 4 | Dark-mode re-audit not performed | Medium | Defer to Issues.md — re-QA task, not a code fix. |
| 5 | Typography still uses Roboto, not Inter | Medium | Defer to Issues.md — known asset-bundling follow-up from UI spike. |
| 6 | `APP_MODE=real` not exercised; `_prodClientId` placeholder | Medium | Defer to Issues.md — real OAuth App registration is a separate workstream. |
| 7 | File-kind chip styling nit (.md vs .pdf) | Low | Defer to Issues.md — cosmetic polish. |
| 8 | Auth state doesn't reset after navigating away | Low (observation) | Defer to Issues.md — plausible behaviour flagged for M1b confirmation. |

## 2. Fix plan (Critical + High only, in severity order)

### Fix 1 — PAT dialog black-screen (Critical)

- **File(s):** `lib/bootstrap.dart`, `lib/ui/screens/sign_in/sign_in_screen.dart`.
- **Root cause (best inference from source):**
  - `_openPatDialog` calls `showDialog` and then `signInWithPat(pat)` against `FakeAuthPort`. In mockup mode `patScript` is empty, so any token throws `AuthInvalidToken`. That alone shouldn't black-screen, but combined with the fact that the mockup composition root never seeds the fake, the dialog opens against a port whose state machine is uninitialised.
  - More load-bearing: `showDialog` with an `AlertDialog` relies on `MaterialApp`/`Directionality`/`MediaQuery` ambient widgets. If the mockup browser shell inserts the SignIn screen under a `DecoratedBox` inside a non-`MaterialApp` ancestor (or a modal route whose barrier defaults to opaque black), the dialog's route renders its default black scrim over the whole Flutter surface while the `AlertDialog` card draws above it — which matches the QA screenshot ("Android status bar over a full-screen black area").
- **Fix approach:**
  - In `sign_in_screen.dart`, pass an explicit `barrierColor: Colors.black54` (or a token-driven scrim) to `showDialog` so the barrier isn't full-opacity black against a missing-theme backdrop.
  - Wrap the `AlertDialog` in a `Theme(data: Theme.of(context).copyWith(dialogBackgroundColor: t.surfaceElevated), child: …)` so `AlertDialog` text styles resolve against the app's tokens instead of defaults.
  - Seed `FakeAuthPort.patScript` inside `_mockupOverrides()` in `bootstrap.dart` with at least one known-good PAT (e.g. `ghp_mockup_demo_token` -> `PatResponse.success(AuthSession(token: …, identity: AuthIdentity(name: 'demo', …)))`) and a scripted error case so the dialog's submit path reaches `AuthSignedIn` instead of silently throwing.
  - Verify the SignIn screen is mounted under `MaterialApp` in the mockup browser root; if not, add one (or a `Material` ancestor) so dialog chrome resolves.
- **Tests:**
  - Widget test: pump the mockup-mode `ProviderScope` at the SignIn screen, tap "Sign in with a token instead", expect the `AlertDialog` to appear with non-null hint text and a visible barrier (`find.byType(AlertDialog)` + `find.text('Paste personal access token')`).
  - Submission path: enter the seeded PAT, dismiss the dialog, expect state to transition to `AuthSignedIn`.
- **Risk / blast radius:** Low — changes are localised to the sign-in screen and the mockup overrides; the `patScript` seed only applies in mockup mode.

### Fix 2 — Device-code panel empty because `nextChallenge`/`pollScript` not seeded (High)

- **File(s):** `lib/bootstrap.dart` (primary). No change needed in `fake_auth_port.dart` or `sign_in_screen.dart`.
- **Root cause:** `_mockupOverrides()` binds `FakeAuthPort()` fresh, so `nextChallenge == null` and `pollScript` is empty. When `AuthController.startDeviceFlow()` calls `_auth.startDeviceFlow()`, the fake throws `StateError('FakeAuthPort.nextChallenge must be set …')`. That matches the QA observation of a panel that *renders* (so the controller transitioned to `AuthDeviceFlowAwaitingUser` briefly, then swallowed) but shows only a stub character — most likely the `StateError` is caught as an `AsyncError` and the panel is showing a stale/empty `userCode`, OR the initial challenge fires with an uninitialised default code. Either way, seeding fixes it.
- **Fix approach:**
  - In `_mockupOverrides()`, construct `FakeAuthPort` as a local, then set `fake.nextChallenge = DeviceCodeChallenge(userCode: 'WDJB-MJHT', verificationUri: 'https://github.com/login/device', deviceCode: 'mock-device-code', expiresAt: DateTime.now().add(const Duration(minutes: 15)), pollInterval: const Duration(seconds: 1))`.
  - Seed `fake.pollScript` with `[PollAuthorizationPending(), PollAuthorizationPending(), PollSuccess(AuthSession(token: 'mock-token', identity: AuthIdentity(name: 'demo', email: 'demo@example.com', …)))]` so the mockup mode auto-completes after ~3s, exercising the awaiting-user → signed-in transition.
  - Keep `authPortProvider.overrideWithValue(fake)` using the same configured instance.
  - Shorten `pollInterval` to ~1s so the mockup-browser walkthrough doesn't stall.
- **Tests:**
  - Widget test: pump mockup ProviderScope at SignIn, tap Continue with GitHub, pump until `AuthDeviceFlowAwaitingUser`, expect `find.text('WDJB-MJHT')` and the caption "Open github.com/login/device and enter this code." to be visible.
  - Pump forward through the poll interval, expect `AuthSignedIn` and the "Signed in as @demo" panel.
- **Risk / blast radius:** Very low — only touches mockup-mode wiring; real-mode overrides untouched; existing `FakeAuthPort` unit tests that script their own challenges continue to pass.

## 3. Issues.md entries (for deferred items)

```markdown
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

### Issue: File-kind chip styling differentiation (.md vs .pdf)
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
```

## 4. Severity disagreements

- **Finding 1 (PAT black-screen)** — QA rated Critical. Agree. This blocks the only documented fallback path for enterprise networks; even in mockup mode a black screen is a showstopper demo bug.
- **Finding 2 (device-code empty)** — QA rated High. I'd argue this is borderline Critical because the primary auth path is unverifiable end-to-end in mockup mode, but because Fix 2 is a trivial mockup-wiring change (~10 lines) and the real adapter would emit a real code, High is defensible. Kept at High; ordered second in fix plan.
- All other findings match QA ratings.

## 5. Dependencies

- Fix 2 (device-code seed) should land **before** Fix 1 (PAT dialog) is smoke-tested end-to-end. Rationale: if the SignIn screen is in an error/uninitialised state because `startDeviceFlow` blew up on `nextChallenge == null`, reproducing the PAT dialog black-screen against a healthy baseline is harder. Land Fix 2, re-QA that the awaiting-user panel renders, then iterate Fix 1.
- The Inter-font Issue has no hard dependency but its visual output will shift — re-QA (dark mode) should run **after** Inter lands to avoid double work.
- The `APP_MODE=real` Issue is gated by the GitHub OAuth App registration (external), not by any other fix.
