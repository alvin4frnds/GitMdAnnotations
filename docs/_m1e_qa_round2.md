# QA round 2 — post-91bbabb
Date: 2026-04-21

## Verification
- Fix A (git repo warm-up on cold start): **PASS** — after force-stop + cold launch, tapping Submit & commit in the review-submit dialog produced the SnackBar "Review committed locally. Push on next Sync Up." No "no repository open" error was emitted (see `small/05-after-submit.png`, bottom-left).
- Fix B (bare-numbered Q&A cards): **PASS** — review panel's right pane rendered four discrete Q&A cards (Q1 magic-link fallback, Q2 refresh-token lifetime, Q3 recovery-code rotation, Q4 block legacy sessions) each with its own "Your answer…" field, plus a separate "Free-form notes" card below (see `small/03-review-panel.png`). The panel is no longer the degenerate "Free-form notes only" state.

## Regression check
- SafeArea still good on pushed routes: **PASS** — Settings screen (`small/06-settings.png`) keeps the AppBar and content below the Android status bar; back arrow is inset from the left edge; nothing is clipped top/left/right. SpecReader and Review routes (`02-specreader.png`, `03-review-panel.png`) also respect insets.
- Annotate panel still shows full spec: **SKIPPED** (out of scope for round 2; screenshot budget preserved for fixes).
- Submit flow end-to-end works (SnackBar appears): **PASS** — full chain JobList → SpecReader → Review panel → Submit review dialog → Submit & commit → SnackBar all executed without error in a single cold-launch session.

## New findings
None. Both previously-identified defects are resolved and no new regressions surfaced during the walkthrough.

## Screenshots
- `docs/_m1e_qa_round2/small/01-cold-launch.png` — JobList after force-stop + cold launch (1 seeded job, surri · claude-jobs header, Sync Down/Up in chrome).
- `docs/_m1e_qa_round2/small/02-specreader.png` — SpecReader for spec-demo showing Auth flow TOTP spec with bare-numbered "Open questions" 1–4.
- `docs/_m1e_qa_round2/small/03-review-panel.png` — Review panel: right pane now shows Q1–Q4 cards plus Free-form notes (evidence for Fix B).
- `docs/_m1e_qa_round2/small/04-submit-dialog.png` — Submit review dialog listing files to be committed and "Offline — will push on next Sync Up." banner.
- `docs/_m1e_qa_round2/small/05-after-submit.png` — Post-submit state with SnackBar "Review committed locally. Push on next Sync Up." (evidence for Fix A).
- `docs/_m1e_qa_round2/small/06-settings.png` — Settings screen with correct SafeArea handling; Account/Repository/Data sections.
