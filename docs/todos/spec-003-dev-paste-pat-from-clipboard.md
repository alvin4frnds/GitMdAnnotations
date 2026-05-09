# Spec 003 — Dev-only "Paste PAT from clipboard" sign-in

**Slug:** dev-paste-pat-from-clipboard  **Status:** Draft  **Authored:** 2026-05-09

---

## 1. Context

In dev, the user keeps having to redo the GitHub OAuth Device Flow because some `flutter run` cycles force a full Android uninstall (signing-mode change, plugin native code change, `flutter clean`), which wipes the app sandbox and with it `flutter_secure_storage`. Even the existing PAT path (`Sign in with a token instead` → `PatDialog` → paste → submit) costs ~4 taps + a paste-menu interaction. The user explicitly rejected baking the token into the binary via `--dart-define`+`dev.env.json` (the token must stay on-device), so we can't make creds survive an `adb uninstall`; we can only minimize the per-reinstall friction.

History a fresh implementer needs:

- **Origin.** This spec was authored in a planning conversation on 2026-05-09 after the user dismissed the dart-define seed approach and explicitly chose "the secure_storage option" — i.e. dev affordance, but token never leaves on-device storage.
- **PAT path is already wired in production.** `lib/ui/screens/sign_in/sign_in_screen.dart:119–134` shows a "Sign in with a token instead" `OutlinedButton` that opens `lib/ui/screens/sign_in/pat_dialog.dart`. `_openPatDialog` at lines 151–164 returns the trimmed token via `Navigator.pop(String)` and calls `ref.read(authControllerProvider.notifier).signInWithPat(pat)` at line 163. `AuthController.signInWithPat` at `lib/app/controllers/auth_controller.dart:78–88` validates via `GET /user` (in `GithubOAuthAdapter.signInWithPat` at `lib/infra/auth/github_oauth_adapter.dart:192–209`), persists `auth.token.v1` + `auth.git_identity.v1` to secure storage, and transitions state to `AuthSignedIn`.
- **Dev-flag pattern to mirror.** `lib/app/dev_seed.dart:14` (`const bool _kDevSeedEnabled = bool.fromEnvironment('DEV_SEED_ENABLED')`) is the existing house style. `lib/bootstrap.dart:38–46` shows the same pattern for `ALLOW_MOUSE_ANNOTATION`.
- **Test-host pattern to mirror.** `test/ui/screens/sign_in/sign_in_screen_test.dart:30–44` (`_host`) builds a `ProviderScope` and overrides `authPortProvider` + `secureStorageProvider` with fakes from `lib/domain/fakes/fake_auth_port.dart` (`patScript: Map<String, PatResponse>` at line 14, with `PatResponse.success(session)` / `PatResponse.error(AuthError)` factories at lines 130–141) and `lib/domain/fakes/fake_secure_storage.dart`.
- **Error-banner contract.** `_ErrorBanner` (`sign_in_screen.dart:281–314`) renders `async.error.toString()` from `AuthController` only on real `AuthError` subtypes (`AuthInvalidToken`, `AuthNetworkFailure` — sealed in `lib/domain/ports/auth_port.dart` per `docs/IMPLEMENTATION.md` §2.3). Non-`AuthError` payloads must NOT enter that pipeline.
- **Architectural rules** (`docs/IMPLEMENTATION.md` §2.3, §2.6, §5.3): typed sealed exceptions only, no business logic in widgets, banned `utils/helpers/common/shared` names, strict TDD (RED → verify failure → GREEN → refactor), fakes over mocks. Function ≤50 lines, max nesting 3. `sign_in_screen.dart` is already 391 lines — an existing deviation from the 200-line guideline; growing it further is acceptable per the same section (split when responsibility, not size, demands it).

## 2. Objective

After this ships, dev builds compiled with `--dart-define=DEV_PAT_QUICK_PASTE=true` show a third button on the SignIn screen labeled "Paste PAT from clipboard". One tap reads the Android system clipboard, validates the format locally, and routes the trimmed token through the existing `AuthController.signInWithPat` path — landing the user on JobList in ≤5 s after a fresh install. Release builds strip the button regardless of the dart-define so the affordance cannot ship to end users.

## 3. Assumptions

- Flutter SDK is FVM-pinned to `stable` (`.fvmrc` → `{"flutter": "stable"}`); SDK constraint `^3.11.5`.
- `flutter_secure_storage` is backed by Android `EncryptedSharedPreferences` (configured in `lib/infra/storage/keystore_adapter.dart:55–62`). App data — and therefore the secure store — survives `adb install -r` but does NOT survive `adb uninstall`.
- The user's PAT will be either a classic token (`ghp_…`) or a fine-grained token (`github_pat_…`). No other prefixes need to be accepted.
- The existing `AuthController.signInWithPat` correctly maps GitHub responses to sealed `AuthError` subtypes: `AuthInvalidToken` on 401, `AuthNetworkFailure` otherwise.
- `Clipboard.getData(Clipboard.kTextPlain)` returns `null` on empty / non-text clipboards; the new code must tolerate `null` and treat it as empty.
- `kReleaseMode` from `package:flutter/foundation.dart` is a compile-time constant; ANDing the dart-define with `!kReleaseMode` enables tree-shaking of the new widget in release builds.

## 4. Out of Scope

- **Persisting creds across `adb uninstall`.** NOT changed because Android scoped storage forbids cross-uninstall data persistence and the user explicitly rejected the host-side `--dart-define`+`dev.env.json` workaround.
- **`AuthController`, `AuthPort`, `GithubOAuthAdapter`, `KeystoreAdapter`, `PatDialog`, `FakeAuthPort`.** NOT changed because the PAT code path is already correct and tested; reusing it is the point.
- **Auto-sign-in on cold start (no tap needed).** NOT changed because it would alter sign-in semantics for production builds and the user did not request it.
- **Hardware-backed Keystore migration.** NOT changed; the existing `EncryptedSharedPreferences` backing is sufficient.
- **`_ErrorBanner` styling.** NOT changed; the new pre-flight errors render in their own local danger text under the new button to avoid contaminating the sealed-`AuthError` channel.
- **Adding a new package dependency.** NOT changed; `Clipboard` is already in `package:flutter/services.dart`, which `sign_in_screen.dart` already imports at line 2.

## 5. Open Questions / `<INPUT_REQUIRED>`

(none — design fully resolved with the user on 2026-05-09)

## 6. Pre-flight Checklist

- [ ] Required skill loaded: `clean-code` (Jeffrey Way / Adam Wathan / Aaron Francis style — short methods, expressive names, early returns)
- [ ] Required skill loaded: `vibesec` (touches auth tokens — never log token contents; validate + trim before submission; do not write tokens to secure_storage from the widget)
- [ ] Required skill loaded: `test-driven-development` (project enforces RED → GREEN → REFACTOR per `docs/IMPLEMENTATION.md` §5.3 — no production code without a failing test first)
- `prod-safety-gate` not required: dev-only feature, stripped in release builds via `kReleaseMode`; no production runtime code path is altered.
- [ ] Working tree clean (`git status` shows only the new branch)
- [ ] Branch is up to date with `origin/main`
- [ ] Read `lib/ui/screens/sign_in/sign_in_screen.dart` (lines 1–166 for `_SignInBody`, 281–314 for `_ErrorBanner`) before editing
- [ ] Read `lib/app/dev_seed.dart` and `lib/bootstrap.dart:38–46` for the dart-define gate pattern
- [ ] Read `test/ui/screens/sign_in/sign_in_screen_test.dart:30–44` (the `_host` helper) — it is the override seam the new tests will extend
- [ ] Re-read AC-1 through AC-10 — implementation must satisfy each

## 7. Acceptance Criteria

- **AC-1**: With `--dart-define=DEV_PAT_QUICK_PASTE=true` (debug build), the SignIn screen renders three buttons in order: "Continue with GitHub", "Sign in with a token instead", "Paste PAT from clipboard". Verify: `find.text('Paste PAT from clipboard'), findsOneWidget` in widget test; visual confirmation on-device.
- **AC-2**: Without the flag (debug build), only the original two buttons render. Verify: `find.text('Paste PAT from clipboard'), findsNothing`.
- **AC-3**: Release build with the flag set does NOT show the new button. Verify: `fvm flutter build apk --release --dart-define=DEV_PAT_QUICK_PASTE=true && adb install -r build/app/outputs/flutter-apk/app-release.apk`; open app; assert visually that only the two original buttons render.
- **AC-4**: Tapping the button with `ghp_<valid>` on the Android clipboard transitions the auth state to `AuthSignedIn`. Verify: widget test seeds `auth.patScript['ghp_mockup_demo_token'] = PatResponse.success(session)`, then asserts `find.text('Signed in as @demo'), findsOneWidget` (mirrors existing test at lines 194–224).
- **AC-5**: Tapping with empty / whitespace-only clipboard surfaces the inline message "Clipboard is empty" under the new button and performs no network round-trip. Verify: widget test asserts `find.text('Clipboard is empty')` and that `auth.patScript` was not queried (left empty + state stays `AuthSignedOut`).
- **AC-6**: Tapping with a token that does NOT start with `ghp_` or `github_pat_` surfaces "Clipboard does not look like a GitHub PAT" and performs no network round-trip. Verify analogously to AC-5.
- **AC-7**: Tapping with `ghp_invalid` (seeded `PatResponse.error(AuthInvalidToken())`) surfaces the error in the existing `_ErrorBanner` at the top of the card; secure_storage is NOT written. Verify: `async.error is AuthInvalidToken` and `find.byType(_ErrorBanner), findsOneWidget`.
- **AC-8**: Tapping with `'  ghp_<valid>\n'` (whitespace-padded) succeeds — the implementation `.trim()`s before validation and submission. Verify: widget test with `clipboardReader: () async => '  ghp_mockup_demo_token\n'` asserts signed-in.
- **AC-9**: All 15 widget tests in `test/ui/screens/sign_in/sign_in_screen_test.dart` pass (5 existing + 10 new). The full `fvm flutter test` suite remains green (no regressions in unrelated screens).
- **AC-10**: `fvm flutter analyze` returns 0 issues. The new widget file and modified test file follow project lints (`flutter_lints/flutter.yaml` per `analysis_options.yaml:10`).
- **AC-OPERATOR**: After merge, the user runs:
  1. `fvm flutter run -d NBB6BMB6QGQWLFV4 --dart-define=DEV_PAT_QUICK_PASTE=true --dart-define=APP_MODE=real`.
  2. Copies a real `ghp_…` PAT from a password manager to the Android clipboard.
  3. Taps "Paste PAT from clipboard". Time-to-JobList ≤ 5 s.
  4. Repeats after `fvm flutter clean && fvm flutter run …` (forces uninstall) — recovery still ≤ 5 s.

## 8. Implementation Guardrails

### 8a. Hard NO list

- Do **NOT** modify `lib/app/controllers/auth_controller.dart` — the PAT path (`signInWithPat` at lines 78–88) is already correct and covered by `test/app/controllers/auth_controller_test.dart`.
- Do **NOT** modify `lib/domain/ports/auth_port.dart`, `lib/domain/entities/auth_session.dart`, `lib/domain/entities/git_identity.dart`, or `lib/domain/fakes/fake_auth_port.dart` — port surface and fake are stable; `patScript` already supports the test cases this spec needs.
- Do **NOT** modify `lib/infra/auth/github_oauth_adapter.dart` or `lib/infra/storage/keystore_adapter.dart`.
- Do **NOT** modify `lib/ui/screens/sign_in/pat_dialog.dart` — the production PAT entry-point stays untouched.
- Do **NOT** modify `_ErrorBanner` (`sign_in_screen.dart:281–314`) or push pre-flight clipboard errors through `async.error` / `AuthController.state`. The sealed `AuthError` channel rejects non-`AuthError` payloads (`docs/IMPLEMENTATION.md` §2.3); pre-flight errors live in the new button widget's local `setState`.
- Do **NOT** introduce a `@visibleForTesting` constructor knob on `SignInScreen` — use `ProviderScope.overrides` in `_host`, matching the existing pattern at `test/ui/screens/sign_in/sign_in_screen_test.dart:34–43`.
- Do **NOT** add a new package dependency. `Clipboard` is already imported via `package:flutter/services.dart` (sign_in_screen.dart line 2).
- Do **NOT** bake the PAT into the binary or any host-side file (the user explicitly rejected `--dart-define=DEV_AUTH_TOKEN=…` + `dev.env.json`).
- Do **NOT** introduce file/class names containing `utils`, `helpers`, `common`, or `shared` — banned by `docs/IMPLEMENTATION.md` §2.6.
- Do **NOT** log clipboard contents at any log level (`developer.log`, `print`, etc.) even in dev builds.

### 8b. Coding / quality principles

- Apply `clean-code`: short widget methods (≤ 50 lines per `docs/IMPLEMENTATION.md` §2.6), expressive names (`_DevPasteFromClipboardButton`, `_preflightError`, `_busy`), early returns inside `_onTap`, no magic numbers (reuse the existing OutlinedButton chrome from line 119–134 verbatim).
- Apply `test-driven-development`: write each new test, run it, verify it fails for the expected reason, then write the smallest production change that makes it pass. Mirror the existing test patterns at lines 47–254. Use `FakeAuthPort.patScript` rather than mocks.
- Apply `vibesec`: trim and validate clipboard input before any network call (AC-5, AC-6); never store the token outside `AuthController` (which already routes it through `KeystoreAdapter`); never log token contents.
- Reuse the existing OutlinedButton style (line 119–134) for the new button so the visual hierarchy stays "GitHub primary > token-dialog secondary > paste-from-clipboard tertiary."
- Use Riverpod providers for both gating and clipboard injection — the codebase's established pattern for "platform thing the test wants to swap." No new mocking libraries.
- Make `_DevPasteFromClipboardButton` a `ConsumerStatefulWidget` so it can both `ref.read` providers and own local UI state (`_preflightError`, `_busy`).
- The button's `onPressed` is `null` while `async.isLoading || _busy` — mirror the existing OutlinedButton's `async.isLoading ? null : ...` pattern at line 120.

## 9. Behavior Spec (per file)

### `lib/app/dev_pat_quick_paste.dart` (new)

- **Current state.** File does not exist.
- **Required edit.** Define `abstract final class DevPatQuickPaste { static bool get enabled => _kFlag && !kReleaseMode; }` with a top-level `const bool _kFlag = bool.fromEnvironment('DEV_PAT_QUICK_PASTE');`. Import `package:flutter/foundation.dart` for `kReleaseMode`. Add a doc comment explaining that release builds always strip the affordance regardless of the flag.
- **Estimated diff.** +20 LOC.
- **Subtle.** `_kFlag && !kReleaseMode` is a compile-time-evaluable boolean. In release builds it folds to `false`, allowing the conditional `children.add(...)` in `sign_in_screen.dart` to be tree-shaken away with the rest of `_DevPasteFromClipboardButton`. Verify by inspecting `flutter build apk --release --analyze-size` if size matters.

### `lib/app/providers/auth_providers.dart`

- **Current state.** Defines `authPortProvider`, `secureStorageProvider`, repo-related providers. No clipboard or dev-gate providers.
- **Required edit.** Add (immediately after the existing auth-related providers):
  - `typedef ClipboardReader = Future<String?> Function();`
  - `final clipboardReaderProvider = Provider<ClipboardReader>((_) => () async => (await Clipboard.getData(Clipboard.kTextPlain))?.text);`
  - `final devPatQuickPasteEnabledProvider = Provider<bool>((_) => DevPatQuickPaste.enabled);`
  - Add imports: `package:flutter/services.dart` and `'../dev_pat_quick_paste.dart'`.
- **Estimated diff.** +12 LOC.
- **Subtle.** Tests in `test/ui/screens/sign_in/sign_in_screen_test.dart` will pass `clipboardReaderProvider.overrideWithValue(() async => 'ghp_…')` — the override closure must match the `Future<String?> Function()` shape exactly.

### `lib/ui/screens/sign_in/sign_in_screen.dart`

- **Current state (391 LOC).** `_SignInBody.build` (lines 62–149) builds a `children` list. The "Sign in with a token instead" `OutlinedButton` block sits at lines 119–134, followed by `SizedBox(height: 20)` at line 135 and the helper text at lines 136–142.
- **Required edit.**
  1. After line 134 (after the closing `),` of `children.add(OutlinedButton(...))`), insert:
     ```
     if (ref.watch(devPatQuickPasteEnabledProvider)) {
       children.add(const SizedBox(height: 8));
       children.add(const _DevPasteFromClipboardButton());
     }
     ```
     The `ref.watch` triggers a rebuild when the test override flips visibility.
  2. At the end of the file (after `_LoadingButton` at line 367–390), add a private `ConsumerStatefulWidget` `_DevPasteFromClipboardButton`. The widget renders a `Column(crossAxisAlignment: stretch)` containing:
     - An `OutlinedButton` styled identically to lines 121–128 (same `foregroundColor`, `side`, padding, shape) labelled `'Paste PAT from clipboard'`. `onPressed` is `null` while `state.isLoading || _busy`; otherwise `() => _onTap(ref)`.
     - When `_preflightError != null`: a `Padding(top: 6, child: Text(_preflightError!, style: TextStyle(color: t.statusDanger, fontSize: 11, height: 1.4)))`.
     - `_onTap(ref)` async logic: read `final reader = ref.read(clipboardReaderProvider);` → `final raw = (await reader()) ?? '';` → `final pat = raw.trim();` → if `pat.isEmpty`: `setState(() => _preflightError = 'Clipboard is empty')`; else if `!pat.startsWith('ghp_') && !pat.startsWith('github_pat_')`: `setState(() => _preflightError = 'Clipboard does not look like a GitHub PAT')`; else: `setState(() { _preflightError = null; _busy = true; })`, `try { await ref.read(authControllerProvider.notifier).signInWithPat(pat); } finally { if (mounted) setState(() => _busy = false); }`.
- **Estimated diff.** +55 LOC; file grows 391 → ~446.
- **Subtle.**
  - `_DevPasteFromClipboardButton` must be `ConsumerStatefulWidget` (not `StatefulWidget`) so its `State` has access to `ref` for both reads and watches.
  - The pre-flight error string lives in local state — it MUST NOT be pushed onto `AuthController.state` (would violate the sealed `AuthError` contract).
  - `mounted` check after the `await` prevents `setState` after dispose.
  - Don't add `import 'package:flutter/services.dart';` — already present at line 2 (used by `_DeviceCodePanelState.initState`).

### `test/ui/screens/sign_in/sign_in_screen_test.dart`

- **Current state (~260 LOC, 5 tests).** `_host` at lines 30–44 builds a `ProviderScope` with overrides for `authPortProvider` and `secureStorageProvider`.
- **Required edit.**
  1. Extend `_host` with two new optional named params: `bool quickPasteEnabled = false` and `ClipboardReader? clipboardReader`. Append corresponding overrides:
     - `devPatQuickPasteEnabledProvider.overrideWithValue(quickPasteEnabled)`
     - `if (clipboardReader != null) clipboardReaderProvider.overrideWithValue(clipboardReader)`
  2. Add the 10 new `testWidgets` cases catalogued in §12b. Each follows the existing house style (lines 47–254): construct `FakeAuthPort` + `FakeSecureStorage`, seed `patScript`, `addTearDown(auth.dispose)`, `pumpWidget(_host(...))`, find + tap, `await tester.pumpAndSettle()`, assertions.
- **Estimated diff.** +250 LOC; file grows ~260 → ~510.
- **Subtle.** For the "disabled while loading" test, gate the `PatResponse` on a `Completer<AuthSession>`. Complete it inside `addTearDown` before the test ends to avoid `flutter_test`'s pending-timer rejection. The disabled assertion is `tester.widget<OutlinedButton>(find.byType(OutlinedButton).last).onPressed == null` while `async.isLoading`.

## 10. Risk / Failure Modes

| Risk | Likelihood | Impact | Mitigation |
| ---- | ---------- | ------ | ---------- |
| Flag accidentally enabled in a release CI pipeline → dev affordance ships to end users | Low | High (secret-paste UI on a published binary) | AC-3 explicitly tests release-mode strip. `DevPatQuickPaste.enabled` ANDs `kReleaseMode`; tree-shaken in release. |
| Clipboard contains a non-PAT secret (Slack token, AWS key, password) and the user taps the button → secret POSTed to `api.github.com/user` | Medium | Medium (secret leaks to GitHub's request log; 401 returned) | AC-6 prefix check (`ghp_` / `github_pat_`) blocks the network call for non-PAT shapes. PAT-shaped secrets are out of scope — same risk as the existing PatDialog. |
| Pre-flight error confused with a real `AuthError` | Low | Low (UX confusion) | Distinct rendering: pre-flight = inline danger text under the new button; real = top-of-card `_ErrorBanner`. AC-5 + AC-7 cover both rendering paths. |
| User double-taps while `signInWithPat` is in flight → duplicate `GET /user` | Low | Low (idempotent network call) | `_busy` flag + `onPressed = null` while loading; mirrors the existing OutlinedButton behaviour at line 120. |
| `Clipboard.getData` throws on a locked / restricted clipboard (rare on Android) | Very low | Low | Treat thrown error as "no clipboard" — wrap in `try { ... } catch { setState empty-message }` inside `_onTap`. |
| `setState` after dispose if the widget pops while `signInWithPat` is in flight | Low | Low (Flutter logs an exception) | `if (mounted) setState(...)` guard around the `_busy = false` update in the `finally` block. |
| File grows past the 200-LOC guideline | Certain | Low (style nit) | `sign_in_screen.dart` is already 391 LOC — pre-existing deviation per `docs/IMPLEMENTATION.md` §2.6. Adding ~55 LOC does not introduce a new violation. |

## 11. Rollback / Revert Plan

1. `git revert <merge-sha>` — clean revert; the change is purely additive across 4 files (1 new, 3 modified) and touches no schema, no migration, no remote state.
2. No env vars to restore. No services to restart.
3. Re-deploy to the dev tablet: `fvm flutter run -d NBB6BMB6QGQWLFV4 --dart-define=APP_MODE=real`.
4. Verify: SignIn screen shows exactly two buttons ("Continue with GitHub", "Sign in with a token instead").
5. Notify: nobody — internal dev affordance, no external impact.

If the only issue is a false-positive in the prefix check (e.g. a future GitHub PAT format), prefer a **forward-fix** (extend the prefix list) over revert; the change is isolated and a one-line edit.

## 12. Verification + Definition of Done

### 12a. Automated verification (implementer runs these)

```bash
fvm flutter analyze
fvm flutter test test/ui/screens/sign_in/sign_in_screen_test.dart
fvm flutter test
```

All three must return `0` errors / `0` failures with no new warnings.

### 12b. Manual QA cases — MANDATORY

#### Frontend / UI cases

| # | Case | Steps | Expected | Status |
| - | ---- | ----- | -------- | ------ |
| FE-1 | Button visible with flag (debug) | `fvm flutter run -d NBB6BMB6QGQWLFV4 --dart-define=DEV_PAT_QUICK_PASTE=true --dart-define=APP_MODE=real`; sign out if signed in | Three buttons rendered in order: GitHub, "Sign in with a token instead", "Paste PAT from clipboard" | Not Run |
| FE-2 | Button hidden without flag (debug) | `fvm flutter run -d NBB6BMB6QGQWLFV4 --dart-define=APP_MODE=real`; sign out | Two buttons only | Not Run |
| FE-3 | Button stripped in release | `fvm flutter build apk --release --dart-define=DEV_PAT_QUICK_PASTE=true && adb -s NBB6BMB6QGQWLFV4 install -r build/app/outputs/flutter-apk/app-release.apk`; open app | Two buttons only | Not Run |
| FE-4 | Valid `ghp_` PAT | Copy `ghp_<real>` from password manager to Android clipboard; tap button | ≤ 2 s → `AuthSignedIn` state (JobList visible, or `_SignedInPanel` "Signed in as @<login>") | Not Run |
| FE-5 | Valid `github_pat_` PAT | Copy `github_pat_<real>`; tap | Same as FE-4 | Not Run |
| FE-6 | Whitespace-padded valid PAT | Copy `'  ghp_<real>\n'` (paste the raw blob with surrounding whitespace); tap | Same as FE-4 (trim works) | Not Run |
| FE-7 | Empty clipboard | `adb -s NBB6BMB6QGQWLFV4 shell am broadcast -a clipper.clear` (or copy a 0-length string from another app); tap | Inline red "Clipboard is empty" under the button; `adb logcat` shows no `api.github.com/user` request | Not Run |
| FE-8 | Malformed token | Copy `notapat`; tap | Inline red "Clipboard does not look like a GitHub PAT"; no network round-trip in logcat | Not Run |
| FE-9 | Invalid PAT (401) | Copy `ghp_invalid`; tap | Top `_ErrorBanner` shows the `AuthInvalidToken` message after the round-trip | Not Run |
| FE-10 | Reinstall recovery | `fvm flutter clean && fvm flutter run -d NBB6BMB6QGQWLFV4 --dart-define=DEV_PAT_QUICK_PASTE=true --dart-define=APP_MODE=real`; copy `ghp_<real>`; tap | ≤ 5 s to JobList | Not Run |

#### Backend / API cases

(none — feature is purely client-side; the existing `GET /user` contract is unchanged.)

**Status values:** `Pass` / `Fail` / `Blocked` / `Not Run`. The implementer fills the Status column as they execute. Any `Fail` or `Blocked` halts the cutover until resolved or explicitly waived by the operator (record any waiver in §5).

### 12c. Definition of Done

The packet is **Shipped** only when ALL are true:

- [ ] Every AC in §7 is satisfied.
- [ ] §12a passes locally (and in CI when CI gains coverage for this repo).
- [ ] Every Manual QA case in §12b has Status ≠ `Not Run` (or has a waiver).
- [ ] No `<INPUT_REQUIRED>` remains in §5.
- [ ] Hard NO list (§8a) was respected — `git diff` on each forbidden file is empty.
- [ ] Rollback plan (§11) was rehearsed mentally; the implementer can articulate it.

---

End of Codex Task Packet — Spec 003
