# Milestone 1c QA — Round 1

## Header

| Field | Value |
|------|------|
| Date | 2026-04-21 |
| Tablet | OnePlus Pad Go 2 (OPD2504), Android 16, id `NBB6BMB6QGQWLFV4` |
| Display | 2800×1980 landscape (physical 1980×2800, rotation 0 via landscape layer stack) |
| Build | M1c HEAD (branch `main`, tip `759ccab`) |
| APK | `build/app/outputs/flutter-apk/app-release.apk`, 46.4 MB |
| APK sha256 | `3559c11549611e9d8c7a45103e4835b116ee6644366c53334510bd0c43433b7b` |
| Connection | Wi-Fi ADB (no USB cable) |
| Reachability limit | **Sign-In screen + PAT dialog only.** Could not complete OAuth Device Flow (blocked by a reproducible Critical bug, see finding F1 below). Could not authenticate via PAT (no token available to this subagent). All post-auth screens — Job List, Spec Reader, Annotation Canvas, Review Panel, Submit Confirmation, Approval Confirmation, Conflict Archived, Changelog Viewer, Settings — are **unreachable in this round**. |

## Screen-by-screen findings

### Sign In — initial (card, pre-interaction)

- Screenshots: `docs/_m1c_qa_round1/10_fresh-launch.png` (clean state after force-stop + relaunch; PAT button enabled, Continue-with-GitHub button enabled).
- Baseline on arrival: `docs/_m1c_qa_round1/01_sign-in-initial.png` — app was already mid-device-flow when I took over, with the Continue-with-GitHub button replaced by a spinner and the PAT button disabled. The provided `launch.png` shows the same stuck-loading state.
- Expected (per IMPLEMENTATION.md §4.8 / docs sign-in mockup): gradient background, centered dark card with brand mark (edit-note icon on accent-soft-bg square), "GitMdScribe" title, one-line subtitle "Sign in with your GitHub account to start reviewing specs.", primary dark "Continue with GitHub" button, outlined "Sign in with a token instead" button below it, and a mono footnote "Device Flow · no backend · token stays in Android Keystore".
- Observed: matches the spec exactly. Typography, spacing, card border-radius, footnote, and gradient all render as intended. Status bar shows running OS notifications (expected).
- Findings:
  - **F3 — Low:** Footnote text wraps mid-phrase: `Device Flow · no backend ·  token stays in Android` / `Keystore` (break between the bullet-dot and "token" leaves an orphaned "Keystore" on line 2). At 380-px max card width the phrase is too long to fit on one line, so soft-wrapping at a space makes sense — but the current wrap places the orphan on the word "Keystore" alone. Consider allowing a slightly wider card on tablets, or breaking the phrase intentionally after the second bullet.

### Sign In — Continue with GitHub (loading / awaiting device code)

- Screenshots:
  - `docs/_m1c_qa_round1/08_device-flow-triggered.png` — state immediately after tapping Continue-with-GitHub (spinner replaces button; PAT button is visibly disabled/greyed).
  - `docs/_m1c_qa_round1/09_device-code-appeared.png` — 8 s later, still spinning.
  - `docs/_m1c_qa_round1/14_after-wait.png` — 13 s after tap (second attempt, same outcome).
- Expected (per sign_in_screen.dart §L110-L116 + IMPLEMENTATION.md §3.5.1): while the POST to `github.com/login/device/code` is in flight, show the spinner button; within a few seconds, transition to `AuthDeviceFlowAwaitingUser` — the card grows to include the `_DeviceCodePanel` with the 8-char user code, "Code copied to clipboard. Paste at github.com/login/device." caption, and the "Copy & open GitHub" CTA. Alternatively, on network failure, transition to `AsyncValue.error` so that `_ErrorBanner` appears above the action row and both buttons re-enable.
- Observed: spinner never resolves. On every one of **three independent attempts** (initial session, first relaunch, second relaunch) the device-flow initiation threw an **Unhandled Exception** in the Flutter isolate — see F1 below — and the UI was left frozen with no user-visible error banner, no device code, and the PAT fallback button disabled.
- Findings:
  - **F1 — Critical:** Unhandled exception when `startDeviceFlow` fails during the first HTTP call; UI wedges with no recovery path. See the dedicated finding block below.

#### F1 — Critical — Unhandled `AuthNetworkFailure` on device-flow kickoff leaves Sign-In stuck with disabled fallback

**Reproducibility:** 3 / 3 attempts in this session.

**Observed logcat (trimmed):**

```
E flutter : [ERROR:flutter/runtime/dart_vm_initializer.cc(40)]
          Unhandled Exception: AuthNetworkFailure(cause: AuthNetworkFailure(cause:
          DioException [connection error]: The connection errored:
          Failed host lookup: 'github.com' …
E flutter : Error: SocketException: Failed host lookup: 'github.com'
          (OS Error: No address associated with hostname, errno = 7)))
E flutter : #0  GithubOAuthAdapter.startDeviceFlow
          (package:gitmdscribe/infra/auth/github_oauth_adapter.dart:81)
E flutter : <asynchronous suspension>
E flutter : #1  AuthController._runDeviceFlow.<anonymous closure>
          (package:gitmdscribe/app/controllers/auth_controller.dart:64)
E flutter : <asynchronous suspension>
```

**Root cause (read-only code inspection — for triage, not a fix):**

1. `GithubOAuthAdapter.startDeviceFlow()` is an `async*` stream (`infra/auth/github_oauth_adapter.dart` L72–L102). When the initial `http.post(_deviceCodeUrl, …)` fails, line 81 does `throw AuthNetworkFailure(e)` before any `yield`.
2. `AuthController._runDeviceFlow()` subscribes with a plain `_auth.startDeviceFlow().listen((c) { … })` — **no `onError` handler, no `cancelOnError`** (`app/controllers/auth_controller.dart` L64). Stream errors therefore escape as unhandled; they are **not** routed into the `Completer` that the outer `try { … } on AuthError` is awaiting.
3. The enclosing `startDeviceFlow()` intent sets `state = AsyncValue.loading()` then `try { final session = await _runDeviceFlow(); … } on AuthError catch (e, st) { state = AsyncValue.error(e, st); }`. Because the stream's throw never makes it into the completer, neither the catch nor any `asyncValue.hasError` branch ever fires. The AsyncNotifier sits forever in `loading`.
4. The `_LoadingButton` replaces the action, and the PAT fallback's `onPressed` is gated by `async.isLoading` → `null` (`sign_in_screen.dart` L120). Net effect: **no way out** except killing the app.

**User-visible impact:**

- No error banner, no toast, no snackbar. Nothing explains what went wrong.
- Both sign-in paths are blocked (primary is a spinner, PAT is disabled).
- A quick device-side check confirms DNS/Internet on the tablet are fine: `ping github.com` resolves to 20.207.73.82 and replies in ~35 ms, and the Wi-Fi network shows `NET_CAPABILITY_VALIDATED`. So the failure is transient-at-app-startup, *not* a user-network problem — making the dead-end UX even worse, because retrying (simply tapping the button again) would almost certainly succeed.

**Why retrying in place doesn't help:**

The flow is stuck in `AsyncValue.loading`; there is no button to tap. Force-stop + relaunch is the only recovery. On this tablet I saw the same exception on three consecutive relaunches — suggesting the Flutter HTTP stack resolves `github.com` through a path that intermittently fails (possibly Private DNS / IPv6; system `UsePrivateDns: true` was set in the ConnectivityManager dump). Whatever the resolver cause, the controller-level bug is what turns an intermittent network glitch into a permanently broken sign-in screen.

**Suggested triage (for whoever picks up the fix — not implemented by this QA pass):**

1. Either convert the stream subscription to `await for (final c in _auth.startDeviceFlow()) { … }` inside the same try/catch, or add an explicit `onError: (e, st) => current.completeError(e, st)` (with `cancelOnError: true`) on the listen.
2. Additionally, treat `AuthNetworkFailure` as retryable at startup — commit `cddc88d` already added retry on transient network errors during *token polling*; the same logic should guard `startDeviceFlow` (the initial POST is at least as vulnerable).
3. Render an error banner + a "Try again" CTA in `AsyncValue.error` state so a wedged user can retry without force-stop.

### Sign In — PAT dialog

- Screenshots: `docs/_m1c_qa_round1/11_pat-dialog.png` (open), `docs/_m1c_qa_round1/12_after-cancel.png` (dismissed — returns to clean sign-in card).
- Expected (per `pat_dialog.dart`): modal with title "Paste personal access token", obscured `TextField` with label "Personal access token" and hint "ghp_…", Cancel + Sign-in actions, scrim at `Colors.black54`, Sign-in disabled until the field is non-empty. The comment at L33-L36 explicitly notes the M1a fix that pins the dialog background to `t.surfaceElevated` to avoid the "black surface" regression.
- Observed: dialog opens correctly, scrim is visible and the correct 54% black, dialog surface is the intended mid-dark (`surfaceElevated`), title, field, and both action buttons render per spec. "Sign in" is disabled (greyed) with an empty field. Tapping Cancel dismisses cleanly. The background sign-in card stays rendered behind the scrim, which matches the mockup.
- Findings:
  - **F4 — Low:** The "Cancel" text button has no visible accent/emphasis and sits next to the (currently disabled) primary "Sign in" button with similar visual weight when Sign in is disabled. Not a functional issue, just a muddy affordance — both look inactive. Re-evaluate once a theme pass lands.

### Sign In — error / recovery path

- Expected: per the docstring on `SignInScreen` (L15-L20), an error state should show an inline error banner above the action row while keeping the main action clickable.
- Observed: **not exercised** because the error never reaches the controller's AsyncValue (F1). If the same underlying DNS failure had been surfaced via `AsyncValue.error`, the banner would have been tested. As is, the spec'd error-state behavior is unverified on-device.
- Findings: covered by F1 (banner path is dead in the current code path for network-level failures during device-code POST).

## Regression check

The M1a mockup browser was removed in commit `153526e`, so the 13-entry visual walk the M1b close-out used as a baseline is no longer reachable from within the app.

What I **can** compare against prior baselines is the real Sign-In screen itself (shipped in M1a, polished in M1a fix-ups):

| Item | M1a/M1b baseline expectation | M1c observation | Verdict |
|------|-------------------------------|------------------|---------|
| Card background / elevation | `surfaceElevated` mid-dark panel on a subtle gradient | Matches | OK |
| Brand mark icon | 56×56 accent-soft-bg with accent-primary edit-note icon | Matches | OK |
| "Continue with GitHub" button styling | dark button, `code_rounded` leading icon, FontWeight.w600 | Matches | OK |
| "Sign in with a token instead" fallback | outlined button, subtle border, enabled in idle state | Matches, and enabled after fresh launch | OK |
| Footnote mono styling | mono 10-px muted | Matches | OK (with F3 noted) |
| PAT dialog scrim / background | 54 % black scrim, `surfaceElevated` dialog surface (M1a "black surface" regression fix) | Matches — no black-surface regression observed | **No regression** |
| SafeArea around the root | Commit `759ccab` wrapped the app root in SafeArea so system bars don't overlap | Status bar is visible at top, content does not sit under it, so the SafeArea wrap appears to be holding | OK |

So: no visual regressions against the M1a/b Sign-In baseline were detected. All regressions on *that* surface are absent.

The rest of the app (the thirteen mockup surfaces that M1b signed off) is **not independently re-verifiable** in this round because the mockup browser is gone and live post-auth screens are unreachable.

## Findings summary

| Severity | Count | IDs |
|---|---|---|
| Critical | 1 | F1 |
| High | 0 | — |
| Medium | 0 | — |
| Low | 2 | F3 (footnote wrap), F4 (PAT dialog button weight) |

**Critical (inline):**

- **F1 — Critical:** Device Flow kickoff throws an unhandled `AuthNetworkFailure` (DNS lookup for `github.com` from inside the Flutter HTTP stack fails intermittently even when system DNS works); the AsyncNotifier never leaves `loading`, the Sign-In screen freezes with no error UI, and the PAT fallback button is disabled. Only recovery is force-stop. Repro rate in this session: **3/3**. Details and proposed triage above.

**High (inline):** none observed — but note the caveat in the next section.

## Notes for triage

1. **Blocked reachability is the dominant story for this round.** Of the M1c-specific surfaces the brief asked me to capture — Review Panel, Submit Confirmation, Approval Confirmation, Conflict Archived, Changelog Viewer, plus the Job List / Spec Reader / Annotation Canvas entry points — **zero were reached**. The only reason is F1. Every other screen is behind `AuthSignedIn`, and the single reliable path into `AuthSignedIn` (Device Flow) wedges on the network call, while the PAT fallback requires a token this subagent does not have. A follow-up round after F1 is fixed (or with a known-good PAT pre-supplied) is required for real M1c coverage.

2. **The "auto-init on launch" described in the task brief was not what I saw.** The brief noted that the device flow auto-initializes on the Sign In screen (with the spinner visible on arrival). On all of my own fresh relaunches after F1 wedged the app, the screen came up in the pristine state with both buttons live — the spinner only appeared after I tapped "Continue with GitHub". So: the "auto-init" I inherited was the residual state of the prior launch (device flow already kicked off and failing), not an opinionated startup path. Worth clarifying in the M1c docs whether auto-start is intended or not.

3. **Regression surface is narrow but green.** The M1a "black surface in PAT dialog" fix is still holding (`PatDialog` pins its background through a local `Theme`), the SafeArea wrap from commit `759ccab` appears correct, and the M1a device-code auto-copy plumbing is in place (though unverified on-device since the device code never rendered). No visible regressions on the Sign-In surface itself.

4. **F1 is the only Critical and there are no Highs or Mediums.** Mechanically, that means M1c's domain-level work (ReviewSerializer / ChangelogWriter / CommitPlanner / ConflictResolver / SyncService.syncUp / ReviewController) cannot be QA'd from the app at all in this round. The unit-test posture of those modules is unchanged; surface QA is just deferred. Once F1 lands a fix and I can hit the Job List, a round-2 QA pass on the seven M1c UI surfaces is recommended before close-out.

5. **Low-severity Lows (F3, F4) are polish, not blockers.** Defer to the Issues.md backlog.

6. **Residual suspicion on Flutter HTTP DNS path.** The tablet's system DNS resolves github.com fine, but the Flutter isolate's HTTP stack threw a `Failed host lookup` on 3 successive attempts. Could be IPv6/IPv4 dual-stack issue, Private DNS mode interaction, or a cold-start DNS cache issue in `package:http` or `package:dio`. Worth investigating in tandem with the F1 controller fix; merely catching the error in the controller would unwedge the UI, but the underlying network-layer flakiness would still surface as repeated user-visible errors.
