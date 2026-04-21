# QA round 1 — post-766d813 bug-fix verification

Date: 2026-04-21
Device: OPD2504 (NBB6BMB6QGQWLFV4), Android 16, OnePlus Pad Go 2
Build: APK from commit `766d813` (the four-bug fix)

The automated QA agent captured 19 screenshots and then hit the same
2000px image-dimension ceiling the M1a QA agent hit — screenshots were
downscaled to 1200px-wide copies in `_m1e_qa_round1/small/` and the
report was finished manually from those.

## Bug-fix verification

### BUG 1 — status bar overlap on tablet → **PASS**

Evidence: screenshots `01-cold-launch.png` (JobList), `02-specreader.png`
(pushed SpecReader route), `03-annotate-canvas.png` (pushed
AnnotationCanvas), `04-review-panel.png` (pushed ReviewPanel),
`15-changelog.png` (pushed ChangelogViewer), `17-settings.png` (pushed
Settings). Every route's first content row sits below the Android
status bar icons — no content is clipped or rendered under the clock /
battery / wifi glyphs. The `MaterialApp.builder` SafeArea wrap applies
to all Navigator routes as intended.

### BUG 2 — annotate panel limited to Open questions + Assumptions → **PASS**

Evidence: `03-annotate-canvas.png`. The canvas now shows the full spec:
Overview, Goals, Non-goals, Open questions, Implementation sketch,
Changelog. The ink overlay sits on top so stylus strokes still land on
whichever part of the rendered markdown the user is drawing over. The
hardcoded two-section stub is gone.

### BUG 3 — review screen hardcoded → **PARTIAL PASS** (spec rendered; Q&A cards missing — see finding #2)

Evidence: `04-review-panel.png`, `05-review-panel-scrolled-right.png`.
Left pane now renders the real spec — title, overview, goals,
non-goals, open questions, implementation sketch, changelog — loaded
from `specFileProvider(jobRef)`. The hardcoded "Auth flow — TOTP
rollout" body that shipped in 766d813 is gone. "No annotations yet"
caption appears in the muted footer slot.

However the right pane shows only "FREE-FORM NOTES" even though the
left pane clearly has four open questions. Root cause: the extractor
required `Q<n>:` id prefix and the real spec uses `1. Should the
flow…`. Filed as finding #2 and fixed in the same round.

### BUG 4 — submit dialog doing nothing → **PASS**

Evidence: `06-submit-dialog.png` → `07-after-submit.png`. Tapping
"Submit & commit" closes the dialog and surfaces a SnackBar with the
concrete result — the test environment shows "Submit failed: Bad
state: GitAdapter: no repository open — call cloneOrOpen first" which
is a separate High-severity defect (finding #1) but proves the dialog
→ caller feedback path works end to end. Cancel also closes the dialog
cleanly with no toast (`09-after-cancel.png`).

## New findings

### Finding #1 — **High** — Submit Review fails after NFR-2 cold-start preload

Screen: Submit confirmation / SnackBar.
Screenshot: `07-after-submit.png`.
Observation: "Submit failed: Bad state: GitAdapter: no repository open
 — call cloneOrOpen first". The user is signed in, the JobList
renders, the spec loads, the preview renders, but the actual commit
throws because the libgit2 isolate never opened the repo.
Reproduction:

1. Cold-start launch (so NFR-2 preload path restores session from
   SecureStorage).
2. Tap the seeded job → Annotate / Review panel → Submit.
3. Dialog → Submit & commit → "no repository open" toast.

Root cause: `GitAdapter.cloneOrOpen` is only called from
`RepoPickerController.pick`. The NFR-2 preload sets
`currentRepoProvider` + `currentWorkdirProvider` but bypasses the
picker, so the isolate's `_repos` map stays empty and every git op
throws.
Fix (landed this round): `JobListController.build` now calls
`gitPort.cloneOrOpen(repo, workdir:)` before loading jobs.
Failures are logged but swallowed so a cold/slow start still shows
the job list; the user sees the real git error only if they actually
try to submit.

### Finding #2 — **Medium** — Review-panel right pane hides Q&A cards for specs that use bare numbered lists

Screen: Review panel, right pane.
Screenshot: `04-review-panel.png`.
Observation: Left pane shows four numbered questions in the "Open
questions" section; right pane shows only "FREE-FORM NOTES" — no
QuestionCards.
Reproduction:

1. Open any job whose spec's "Open questions" section uses
   `1. Foo?` / `- Foo?` without the `Q<n>:` prefix.
2. Tap Review panel.
3. Right pane is missing the Q1..Qn cards that the PRD shows.

Root cause: `OpenQuestionExtractor` required every entry to start
with the literal `Q<digits>` id. Real-world specs that just number
their questions slipped through unrecognised.
Fix (landed this round): extractor grew bare-numbered and
bare-bullet fallbacks that synthesise `Q<position>` ids.

## Screenshots taken (19)

- `01-cold-launch.png` — JobList after cold start; NFR-2 preload restored session.
- `02-specreader.png` — Pushed SpecReader route; real markdown rendering.
- `03-annotate-canvas.png` — Pushed AnnotationCanvas; full spec behind ink overlay (BUG 2 ✅).
- `04-review-panel.png` — Pushed ReviewPanel; real spec on left, "FREE-FORM NOTES" only on right (finding #2).
- `05-review-panel-scrolled-right.png` — Same, scroll attempt.
- `06-submit-dialog.png` — Submit & commit confirmation modal.
- `07-after-submit.png` — Dialog closed + SnackBar with error (BUG 4 ✅; finding #1).
- `08-submit-dialog-again.png` — Re-opened the submit dialog.
- `09-after-cancel.png` — Cancel closes dialog with no toast (BUG 4 ✅).
- `10-back-from-review.png` — Pop back to AnnotationCanvas.
- `11-back-to-joblist.png` — Further pop back.
- `12-back2.png` — Another pop.
- `13-joblist.png` — JobList (same as 01).
- `14-filter-awaiting-review.png` / `14b-*` — Filter rail tap on "Awaiting review".
- `15-changelog.png` — Pushed ChangelogViewer.
- `16-back-from-changelog.png` — Pop back.
- `17-settings.png` — Pushed Settings (account / repository / data).
- `18-back-from-settings.png` — Pop back.
- `19-sync-down-tap.png` — Sync Down tap.

## Triage outcome

Critical: 0
High: 1 → fixed this round (finding #1).
Medium: 1 → fixed this round (finding #2).
Low: 0 new (pre-existing items remain in `docs/Issues.md`).

Proceeding to a round-2 QA pass on the next APK deploy.
