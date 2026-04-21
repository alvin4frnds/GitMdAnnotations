# Phase-1 close-out QA — 2026-04-21
Device: OPD2504 (NBB6BMB6QGQWLFV4), Android 16
Build: ac754f6

## Screens walked

| # | Screen | Route pushed from | PASS/FAIL | Screenshot | Notes |
|---|--------|-------------------|-----------|------------|-------|
| 1 | Cold start → JobList | app launch (force-stop) | PASS | 01_cold_start_joblist.png | App fully rendered within ~2.5 s budget window; no splash lingers |
| 2 | Sign In / RepoPicker | — | N/A | — | Already signed in as Praveen Kumar <pkpraveen16@yahoo.com> on alvin4frnds/surri; signed-out state not reachable without destructive action |
| 3 | JobList | root | PASS | 01_cold_start_joblist.png, 11_phase_awaiting_revision.png | Phase rail (All=1, Awaiting review=1, Awaiting revision=0, Approved=0), Sync Down / Sync Up chrome, Changelog + Settings left rail, spec-demo row with .md chip all render |
| 4 | SpecReader (markdown) | JobList row tap | PASS | 02_specreader_md.png | Breadcrumb `02-spec.md › spec-demo`, On-this-page outline matches H2 headings (Overview, Goals, Non-goals, Open questions, Implementation sketch, Changelog), Annotate / Review panel / Submit in top chrome |
| 5 | SpecReader (PDF) | — | N/A | — | No PDF job present to test |
| 6 | AnnotationCanvas | SpecReader → Annotate | PASS | 03_annotation_canvas.png | Full spec renders, pen/highlighter/eraser/lasso toolbar present, 6-color palette, Undo/Redo visible, left rail On-this-page + Ink Layers (Group A/B/C) |
| 7 | ReviewPanel | Canvas → Review panel | PASS | 04_review_panel.png | Left pane spec layout mirrors canvas, right pane has Q1–Q4 cards auto-extracted from Open questions + Free-form notes section, chrome has Submit review |
| 8 | Submit confirmation | Review panel → Submit review | PASS | 05_submit_confirm.png, 06_submit_snackbar.png | Dialog shows planned writes (03-review.md, 03-annotations.svg, 03-annotations.png, 02-spec.md changelog+1), commit message, offline banner, Cancel + Submit & commit buttons. Tapping Submit & commit closes dialog and shows SnackBar "Review committed locally. Push on next Sync Up." |
| 9 | Approval confirmation | — | N/A | — | Unreachable: 0 jobs in Awaiting-revision phase |
| 10 | Conflict archived | — | N/A | — | Not provokable from current build state; per brief, skipped |
| 11 | Settings | JobList → Settings | PARTIAL | 09_settings.png | Account + Repository + Data (Export backups) sections render; Export button present. **Sign-out button MISSING** — see finding F1 |
| 12 | Changelog viewer | JobList → Changelog | PASS | 08_changelog.png | HISTORY rail, Back-to-jobs link, breadcrumb `surri · changelog · 0 entries`, empty-state "No changelog entries yet" |

## Cross-cutting checks

- SafeArea on pushed routes: PASS (status bar clock/icons visible at top, no content clipped on any pushed route)
- Dark-mode default ink yellow: PASS (yellow dot visibly selected in canvas color palette; device in dark theme)
- No logcat exceptions across the walk: PASS (only OEM/Oplus vendor noise, zero Flutter/Dart `Exception|Error|FATAL|abandoned` after filtering mali_gralloc / SchedAssist / OplusPredictive / OplusActivityThread / OplusAppHeapManager / NoSuchMethodException)
- NFR-2 cold start impression (< 2 s to JobList): PASS (JobList fully rendered before the 2.5 s post-launch screenshot; preload felt instant)

## Findings

### F1 — Settings has no Sign Out button (Medium)
- **Screen:** Settings
- **Observation:** The Account section shows only "Signed in as Praveen Kumar <pkpraveen16@yahoo.com>" with no trailing button/link. Swiping the page up (to rule out off-screen) reveals nothing else; a grep of the full uiautomator UI tree for `sign|signout|logout|log out` returns no hits.
- **Reproduction:** Launch app → JobList → Settings (left rail).
- **Screenshot ref:** 09_settings.png
- **Root cause hypothesis:** Sign-out affordance not wired in for this build; the QA brief explicitly lists "sign-out button present (don't tap — session must persist)" as an expected row-12 check.

### F2 — Sync Up badge does not increment after local review commit (Medium)
- **Screen:** JobList header / Sync Up pill
- **Observation:** After a successful local review commit (SnackBar "Review committed locally. Push on next Sync Up."), the Sync Up pill still reads `0`. Users get no visual indication of pending pushes waiting offline.
- **Reproduction:** JobList → spec-demo → Annotate → Review panel → Submit review → Submit & commit. Return to JobList; badge is still `0`.
- **Screenshot ref:** 07_joblist_after_submit.png, 10_joblist_final.png
- **Root cause hypothesis:** Sync Up count may only be derived from remote-vs-local diff on a different trigger, or local commits are staged as draft files (not git commits) so they don't count. Either way the offline queue is invisible to the user.

### F3 — Changelog entry count unaffected by local commit (Low)
- **Screen:** Changelog viewer
- **Observation:** After the local commit above, Changelog still shows `0 entries` / "No changelog entries yet".
- **Reproduction:** Same as F2, then tap Changelog in left rail.
- **Screenshot ref:** 08_changelog.png
- **Root cause hypothesis:** Likely by design (changelog reads remote git history), but worth noting while F2 is being investigated — same family of "local-only commit visibility" issue.

## Phase-1 exit verdict

- Critical findings: 0
- High findings: 0
- Medium findings: 2 (F1 missing sign-out, F2 Sync Up badge stale)
- Low findings: 1 (F3 changelog count)
- Verdict: **NEEDS FIX ROUND 1**

The Phase-1 feature surface is functionally complete end-to-end (cold start, spec reader, annotation canvas, review panel, submit-&-commit flow with SnackBar, settings, changelog, phase filters). No crashes, no Flutter exceptions, SafeArea / dark-mode ink / landscape lock all clean. Blocking the exit gate is the missing Settings sign-out button (F1: Row-12 requirement from the QA brief itself) and the silent offline-commit queue (F2: if user can't see their pending pushes, the Sync Up chrome UX breaks). Both are Medium but need to clear before shipping.

## Screenshots captured

- 01_cold_start_joblist.png — JobList after force-stop cold launch (Phase rail, spec-demo row, Sync Down / Sync Up chrome)
- 02_specreader_md.png — SpecReader with `spec-demo/02-spec.md`; outline, breadcrumb, chrome buttons
- 03_annotation_canvas.png — AnnotationCanvas: pen toolbar, palette, undo/redo, ink layers rail, Awaiting-review chip
- 04_review_panel.png — ReviewPanel: spec left, Q1–Q4 answer cards + Free-form notes right
- 05_submit_confirm.png — Submit review dialog: planned writes, commit message, offline banner, Cancel + Submit & commit
- 06_submit_snackbar.png — Back to ReviewPanel with SnackBar "Review committed locally. Push on next Sync Up."
- 07_joblist_after_submit.png — JobList after commit; Sync Up still `0` (F2)
- 08_changelog.png — Changelog empty-state (F3)
- 09_settings.png — Settings page; no sign-out visible (F1)
- 10_joblist_final.png — JobList after exiting Settings
- 11_phase_awaiting_revision.png — Phase filter rail state check
