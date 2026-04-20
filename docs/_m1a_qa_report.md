# M1a QA Report — 2026-04-20

## Environment

- Deploy: M1a close-out, APP_MODE=mockup
- Tablet: OnePlus Pad Go 2 (Android 16, arm64)
- Display: 1980×2800 physical (landscape 2800×1980 content)
- Screenshots: `C:/Users/Praveen/AppData/Local/Temp/m1a_qa/` (23 files)

The automated QA subagent captured all 23 screenshots but hit an image-dimension ceiling before writing the report; this review is authored by the main thread from a spot-check of the critical interaction paths (SignIn default, SignIn after tap, SignIn after PAT-dialog open, Job list loaded).

## Highlights

- Mockup browser shell, left rail, and theme toggle still function as approved in the UI spike.
- Job list screen has been successfully re-wired to the real `JobListController` without visual regression — phase pills, file-kind chips, and layout match the mockup.
- Sign in screen transitions out of `AuthSignedOut` into a different state after the GitHub button is tapped, confirming the Riverpod plumbing is live.

## Screen-by-screen findings

### 1. Sign in

- Screenshots: `02_sign_in_default.png` (default), `03_sign_in_tapped.png` (mid-transition), `03b_sign_in_devicecode.png` (awaiting-user state), `18_pat_dialog_open.png` (PAT dialog attempt).
- **[Critical] PAT dialog opens into a fully black surface.** `18_pat_dialog_open.png` shows only the Android status bar over a full-screen black area — the entire Flutter surface has gone black once the PAT dialog opens. Either the dialog renders but its content is unstyled (no card, no text) under an opaque-black barrier, or the app is in a broken state mid-paint. Users cannot complete the PAT fallback path, which is the documented workaround for enterprise networks that block the Device Flow.
- **[High] Device-code panel renders without a code.** `03b_sign_in_devicecode.png` shows the post-tap `AuthDeviceFlowAwaitingUser` state with an empty light-indigo panel containing only a small punctuation mark; the expected large-mono `userCode` (e.g. `WDJB-MJHT`) and the "Open github.com/login/device and enter this code." caption are invisible. Root cause is almost certainly that the mockup-mode composition root does not seed `FakeAuthPort.nextChallenge` / `pollScript`, so the stream yields a default/empty `DeviceCodeChallenge`. Tapping the button should produce a plausible-looking code + caption.

### 2. Sync Down (stub)

- Screenshot: `04_sync_down.png`.
- No regressions vs UI spike.

### 3. Job list

- Screenshot: `05_job_list.png`.
- **[Medium] "Just arrived" visual treatment is missing from the first job row.** Pre-wiring the first row had an `accentSoftBg` background + 4px left border + "just arrived" inline label; now that the screen is fed through `JobListController`, this treatment is dropped because `Job` carries no sync-arrival metadata. Already flagged as a follow-up in the T12 commit; captured here for the defect ledger.
- **[Low] Phase-tag order is unchanged.** All three rows show "Awaiting review" / "Awaiting revision" pills correctly coloured; icon-less file-kind chip spacing matches the original.

### 4. Spec reader (markdown) — stub

- Screenshot: `06_spec_reader.png`. No regressions.

### 5. Annotation canvas — stub

- Screenshot: `07_annotation_canvas.png`. No regressions.

### 6. Review panel — stub

- Screenshot: `08_review_panel.png`. Hand-drawn wobbly stroke hints still render correctly.

### 7. Submit confirmation — stub

- Screenshot: `09_submit_confirmation.png`. No regressions.

### 8. Sync Up — stub

- Screenshot: `10_sync_up.png`. No regressions.

### 9. Changelog viewer — stub

- Screenshot: `11_changelog.png`. No regressions.

### 10. Approval confirmation — stub

- Screenshot: `12_approval.png`. No regressions.

### 11. Conflict archived — stub

- Screenshot: `13_conflict.png`. No regressions.

### 12. New spec (Phase 2) — stub

- Screenshot: `14_new_spec.png`. No regressions.

## Mockup browser / shell

- Left rail: 12 items visible, selected state highlights in `accentSoftBg` + `accentPrimary` text.
- Theme toggle: captured only in light mode during this QA pass (agent terminated before the dark-mode re-walk). **[Medium]** re-audit dark mode in a follow-up QA round.
- `15_sign_in_back.png` / `17_relaunch.png` indicate the user code panel does not automatically return to the default state after navigating away — this is plausible behaviour (auth state is process-global) but we should confirm the recovery UX in M1b.

## Cross-cutting

- **[Medium] Typography still uses system Roboto, not Inter.** Known follow-up from the UI spike; asset fonts haven't been bundled yet.
- **[Medium] No visible confirmation that the real OAuth flow would work end-to-end.** `APP_MODE=real` was not exercised in this QA pass; separately, `bootstrap._prodClientId` is a placeholder, so there is no device integration test to run yet.

## Summary

| Severity | Count | Items                                                                                   |
|----------|-------|------------------------------------------------------------------------------------------|
| Critical | 1     | PAT dialog renders black-screen.                                                         |
| High     | 1     | Device-code panel empty because mockup mode doesn't seed `FakeAuthPort.nextChallenge`.   |
| Medium   | 4     | "Just arrived" row treatment, Inter font not bundled, dark-mode re-audit, `APP_MODE=real` not exercised. |
| Low      | 1     | File-kind chip styling nit (neutral, may benefit from slight accent per .md / .pdf).     |

**Top 3 things to fix before M1a close-out**

1. PAT dialog black-screen. (Critical — blocks the core auth fallback path.)
2. Device-code panel empty state. (High — the main auth flow's awaiting-user UI is unverifiable.)
3. Dark-mode re-audit (not blocking close-out, but would surface any light-mode-only findings).

2/6 findings are Critical+High; report at `docs/_m1a_qa_report.md`.
