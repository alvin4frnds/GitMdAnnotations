# GitMdScribe / GitMdAnnotations — Manual Test Cases

> Human-executable test-case spec for the Phase 1 tablet review cockpit (Milestones 1a–1d of [IMPLEMENTATION.md](IMPLEMENTATION.md)).
> Source of truth for what the app should do: [PRD/TabletApp-PRD.md](PRD/TabletApp-PRD.md).
> Current milestone state: [PROGRESS.md](PROGRESS.md).

---

## 0. Preamble

### 0.1 Device under test

- **Tablet:** OnePlus Pad Go 2 (OPD2504), Android 16, arm64, display 2800x1980. Pressure-sensitive active stylus paired.
- **Device id (ADB):** `NBB6BMB6QGQWLFV4`.
- **Build variant:** release APK, real mode (`APP_MODE=real`) unless a TC explicitly says mockup. Mockup-mode TCs exist because `APP_MODE=mockup` seeds the `FakeAuthPort` / `FakeFileSystem` that back the 13-screen mockup browser.

### 0.2 Pre-flight for every run

1. Release APK installed: `fvm flutter build apk --release --flavor prod` then `adb -s NBB6BMB6QGQWLFV4 install -r build/app/outputs/flutter-apk/app-prod-release.apk`.
2. GitHub account has a test repo with:
   - default branch `main` containing at least one folder under `jobs/pending/` on the `claude-jobs` branch with `02-spec.md`;
   - a second job containing `spec.pdf` + sidecar `CHANGELOG.md`;
   - a third job containing `02-spec.md` + `03-review.md` + `04-spec-v2.md` (phase = `revised`) for Approve coverage.
3. Fine-grained PAT with `contents:write` + `metadata:read` on that repo, kept alongside this doc in the tester's password manager.
4. Wi-Fi on. Mobile data off unless a TC overrides.
5. System UI mode set to Light for the first pass; repeat the theme-sensitive TCs in Dark.

### 0.3 Reset state between runs

- Full reset: `adb -s NBB6BMB6QGQWLFV4 shell pm clear in.xuresolutions.gitmdscribe`.
- Partial reset (keep token, wipe cache): sign out via Settings, then re-sign-in.
- Backup folder inspection: `adb -s NBB6BMB6QGQWLFV4 shell run-as in.xuresolutions.gitmdscribe ls files/backups/`.
- Screenshot: `adb -s NBB6BMB6QGQWLFV4 exec-out screencap -p > <tc-id>.png`.
- Logcat during a TC: `adb -s NBB6BMB6QGQWLFV4 logcat -c` before the run, `adb ... logcat -d > <tc-id>.log` after.

### 0.4 Severity rubric

- **Critical:** data loss, unrecoverable state, security leak, app unusable.
- **High:** user-visible functional break with a workaround; blocks the core review loop.
- **Medium:** annoyance, degraded UX, cosmetic on a primary surface.
- **Low:** cosmetic on a secondary surface, copy, spacing.

---

## 1. Table of Contents

| Area | Range | Count |
|---|---|---|
| Auth (Sign in, PAT, Sign out) | TC-AUTH-01 to TC-AUTH-07 | 7 |
| Repo picker | TC-REPO-01 to TC-REPO-05 | 5 |
| Job list + filters + changelog timeline | TC-JOBS-01 to TC-JOBS-06 | 6 |
| Spec reader (markdown) | TC-MD-01 to TC-MD-05 | 5 |
| Spec reader (PDF) | TC-PDF-01 to TC-PDF-04 | 4 |
| Annotation canvas | TC-INK-01 to TC-INK-09 | 9 |
| Review panel | TC-REV-01 to TC-REV-05 | 5 |
| Submit confirmation | TC-SUB-01 to TC-SUB-05 | 5 |
| Approve confirmation | TC-APR-01 to TC-APR-03 | 3 |
| Conflict archived flow | TC-CONF-01 to TC-CONF-03 | 3 |
| Settings | TC-SET-01 to TC-SET-04 | 4 |
| Sync status bar | TC-SYNC-01 to TC-SYNC-04 | 4 |
| Cross-cutting (SafeArea, orientation, NFR-2) | TC-CC-01 to TC-CC-04 | 4 |
| Regression tests for 766d813 fixes | REG-BUG-1 to REG-BUG-4 | 4 |

**Total: 68 test cases.**

---

## 2. Auth — Sign in, PAT, Sign out

### TC-AUTH-01: Fresh install routes to Sign In
**Preconditions:** app data cleared.
**Steps:**
1. Launch the app icon.
**Expected result:** Sign In screen is the first route; no jobs or repo picker visible; status bar does not overlap the app bar (see REG-BUG-1).
**Severity if fails:** Critical

### TC-AUTH-02: Device Flow happy path (real mode)
**Preconditions:** signed out. OAuth App registered with a valid `client_id`.
**Steps:**
1. Tap "Sign in with GitHub".
2. Confirm the `user_code` (e.g. `WDJB-MJHT`) is visible and a Chrome Custom Tab opens `github.com/login/device`.
3. Approve the scope in the browser.
4. Return to the app.
**Expected result:** App polls and within ~5 s lands on the Repo Picker. Token + `(name, email)` written to the Keystore (verified via next cold-launch skipping Sign In).
**Severity if fails:** Critical

### TC-AUTH-03: Device Flow mockup-mode stub
**Preconditions:** app built with `APP_MODE=mockup` (or default). Sign In shown.
**Steps:**
1. Tap "Sign in with GitHub".
**Expected result:** Device-code panel displays the scripted `WDJB-MJHT` code + caption. Proceeds to Repo Picker after scripted poll.
**Severity if fails:** High

### TC-AUTH-04: PAT fallback — valid token
**Preconditions:** signed out. Valid fine-grained PAT in clipboard.
**Steps:**
1. Tap "Sign in with a token instead".
2. Paste the PAT into the dialog.
3. Tap "Sign in".
**Expected result:** Dialog closes cleanly (no black OPPO secure-IME overlay — see PROGRESS.md M1a round-2 fix). App lands on Repo Picker. Token persisted.
**Severity if fails:** High

### TC-AUTH-05: PAT fallback — invalid token
**Preconditions:** signed out. Obviously invalid PAT string (e.g. `ghp_invalid_xxx`).
**Steps:**
1. Open the PAT dialog, paste the bogus token, tap "Sign in".
**Expected result:** `/user` 401 is surfaced as "Invalid token"; input field cleared; dialog stays open for retry; no token stored.
**Severity if fails:** High

### TC-AUTH-06: Revoked-token recovery
**Preconditions:** signed in with a session. Tester can revoke at `github.com/settings/applications`.
**Steps:**
1. Revoke the app authorization on GitHub.
2. Return to the tablet and tap Sync Up.
**Expected result:** First 401 discards the stored token, user is routed back to Sign In; no silent retry loop. After re-auth the next Sync Up succeeds.
**Severity if fails:** High

### TC-AUTH-07: Sign out clears token + last-session keys
**Preconditions:** signed in; at least one repo has been opened (so last-session keys are populated).
**Steps:**
1. Open Settings.
2. Tap "Sign out".
3. Kill the app, relaunch.
**Expected result:** Sign In is the first route. No cold-start preload to a stale JobList. Keystore entry cleared (verified by `adb logcat` showing no `currentSession` hit on next launch).
**Severity if fails:** High

---

## 3. Repo picker

### TC-REPO-01: List repos the user has access to
**Preconditions:** fresh sign-in.
**Steps:**
1. Observe the Repo Picker.
**Expected result:** Paginated list of the signed-in user's repos. "Last opened" list is empty on first run.
**Severity if fails:** High

### TC-REPO-02: Search / filter
**Preconditions:** Repo Picker visible with >5 repos.
**Steps:**
1. Type a partial repo name into the search field.
**Expected result:** List filters in real time; clearing the field restores full list.
**Severity if fails:** Medium

### TC-REPO-03: Pick a repo → Job List
**Preconditions:** Repo Picker visible.
**Steps:**
1. Tap a repo with known `claude-jobs` branch.
**Expected result:** App navigates to Job List. Sync status bar shows "last synced: never" or "N jobs cached". Status bar does not overlap app bar.
**Severity if fails:** Critical

### TC-REPO-04: Last-opened shortcut
**Preconditions:** At least one repo opened previously; cold start.
**Steps:**
1. Launch the app.
**Expected result:** Cold-start preload (NFR-2) takes the user directly to the last-opened JobList within 2 s on Wi-Fi / 3 s offline (see TC-CC-04).
**Severity if fails:** High

### TC-REPO-05: Non-default branch repo
**Preconditions:** A test repo whose default branch is `develop` (not `main`).
**Steps:**
1. Pick this repo.
2. Observe Sync Down result.
**Expected result:** App detects the non-`main` default via GitHub API and bootstraps `claude-jobs` from `develop`. No error about missing `main`.
**Severity if fails:** High

---

## 4. Job list + filters + changelog timeline

### TC-JOBS-01: Lists folders under `jobs/pending/`
**Preconditions:** Signed in; Sync Down completed; fixture repo has 3 jobs.
**Steps:**
1. Observe Job List.
**Expected result:** 3 rows, one per `spec-<id>` folder. Each shows: job id, derived phase chip (spec / review / revised / approved), last-modified, 2-line preview.
**Severity if fails:** High

### TC-JOBS-02: Phase chip truth table
**Preconditions:** Jobs present for each of {spec, review, revised, approved}.
**Steps:**
1. Scan the phase chips.
**Expected result:** `{02-spec.md}` → spec; `{02,03}` → review; `{02,03,04-*}` → revised; any folder containing `05-approved` → approved.
**Severity if fails:** High

### TC-JOBS-03: Tap row → opens correct Spec Reader
**Preconditions:** Job List with both a markdown job and a PDF job.
**Steps:**
1. Tap the markdown job.
2. Back out; tap the PDF job.
**Expected result:** First tap routes to Spec Reader (md); second to Spec Reader (PDF). Route chosen by `SourceKind` derived from filesystem, not hardcoded.
**Severity if fails:** Critical

### TC-JOBS-04: Unpushed-commit badge
**Preconditions:** At least one local commit not yet pushed (e.g. after Submit Review).
**Steps:**
1. Return to Job List.
**Expected result:** Badge on the Sync Up affordance shows the unpushed count (FR-1.31). Clearing via Sync Up resets the count to 0.
**Severity if fails:** Medium

### TC-JOBS-05: Changelog viewer from Job List
**Preconditions:** A job with `## Changelog` section containing ≥3 entries (some `tablet:`, some `desktop:`).
**Steps:**
1. Tap the changelog-viewer affordance on the Job List left rail.
**Expected result:** Chronological timeline renders all entries across all jobs, newest first, with author badge. Entries are human-readable, one line each. PDF jobs' sidecar `CHANGELOG.md` is merged into the same timeline.
**Severity if fails:** Medium

### TC-JOBS-06: Empty-state (no jobs yet)
**Preconditions:** Repo whose `claude-jobs` exists but has no `jobs/pending/` entries.
**Steps:**
1. Open that repo.
**Expected result:** Empty state copy explaining "No open jobs yet — desktop writes `02-spec.md` here." No crash. Sync Down still operable.
**Severity if fails:** Medium

---

## 5. Spec reader (markdown)

### TC-MD-01: Renders CommonMark + GFM
**Preconditions:** `02-spec.md` contains headings H1–H4, a table, a task list, strikethrough, a fenced code block, an inline link, and a blockquote.
**Steps:**
1. Open the job.
**Expected result:** All elements render per GFM. Code block is read-only, syntax-highlighted; heading hierarchy is legible.
**Severity if fails:** High

### TC-MD-02: Heading nav rail + sticky section header
**Preconditions:** A long markdown spec (≥6 H2 sections).
**Steps:**
1. Open the heading nav rail.
2. Tap a deep heading.
3. Scroll up/down.
**Expected result:** Tapping jumps to the heading. Sticky section header updates as the viewport crosses heading boundaries.
**Severity if fails:** Medium

### TC-MD-03: Typography — ~40 chars/line
**Preconditions:** Wide paragraph content in the spec.
**Steps:**
1. Measure line width by eye (or via screenshot overlay).
**Expected result:** Body text targets ~40 chars/line (FR-1.11). Code blocks may exceed.
**Severity if fails:** Low

### TC-MD-04: Dark-mode readability
**Preconditions:** System or in-app theme set to dark.
**Steps:**
1. Open the markdown spec.
**Expected result:** Background matches `surface/background` dark token (`#0A0A0B`); code blocks, blockquotes, tables all have tuned dark colors; no pure-white flashes anywhere on screen.
**Severity if fails:** Medium

### TC-MD-05: Missing spec file (corrupt job folder)
**Preconditions:** A job folder that has `03-review.md` but no `02-spec.md`.
**Steps:**
1. Tap the job.
**Expected result:** Spec Reader shows a typed error state ("Spec missing for this job") — no raw exception bubble. Back nav works.
**Severity if fails:** High

---

## 6. Spec reader (PDF)

### TC-PDF-01: Page-by-page render + fit-to-width
**Preconditions:** A job with a multi-page `spec.pdf`.
**Steps:**
1. Open the PDF job.
**Expected result:** Pages render in order, fit-to-width default. Left rail shows page list. First 2–3 pages lazy-load; later pages only rasterize as they scroll into view.
**Severity if fails:** High

### TC-PDF-02: Pinch-zoom
**Preconditions:** A PDF page open.
**Steps:**
1. Pinch-zoom with two fingers.
2. Pinch-zoom-out.
**Expected result:** Page scales smoothly; no tearing of the overlay layer; stroke overlay stays anchored to the page's content coordinates on re-render.
**Severity if fails:** Medium

### TC-PDF-03: Scroll FPS on a large PDF
**Preconditions:** A PDF with ≥ 100 pages.
**Steps:**
1. Scroll rapidly through the PDF.
**Expected result:** Target 60 FPS. Memory residency < 200 MB (LRU holds ~8 pages max per `PdfPageCache`).
**Severity if fails:** Medium

### TC-PDF-04: Render-error fallback
**Preconditions:** A deliberately corrupted PDF (truncated bytes) in a job folder.
**Steps:**
1. Open the PDF job.
**Expected result:** Per-page error box ("Failed to render page N") rather than a crash; other functional pages still render; back nav works.
**Severity if fails:** High

---

## 7. Annotation canvas

### TC-INK-01: Stylus draws, finger does not (palm rejection)
**Preconditions:** Annotation canvas open on a markdown spec. Stylus paired.
**Steps:**
1. Rest a palm + index finger on the canvas while drawing a stroke with the stylus.
2. Briefly draw with a fingertip only.
**Expected result:** Stylus produces a stroke; the simultaneous finger contact scrolls or is ignored but never creates ink; the fingertip-only stroke does not create ink.
**Severity if fails:** Critical

### TC-INK-02: Pressure sensitivity visible
**Preconditions:** Pen tool selected, black ink.
**Steps:**
1. Draw one stroke applying increasing pressure from start to end.
**Expected result:** Stroke width visibly increases with pressure along the stroke. No single-width line.
**Severity if fails:** High

### TC-INK-03: Latency budget (NFR-1 <25 ms)
**Preconditions:** Canvas open; stylus connected.
**Steps:**
1. Draw a long freehand stroke, observing the trailing gap between pen tip and rendered ink.
**Expected result:** Felt-experience "feels like paper" (PRD M-4); gap visually ≤ 1 stroke-width.
**Severity if fails:** High

### TC-INK-04: All 6 ink colors + eraser
**Preconditions:** Canvas open.
**Steps:**
1. In sequence: pick each of black, red, blue, green, yellow, orange; draw a short stroke with each.
2. Pick the eraser; drag across two of the strokes.
**Expected result:** Each stroke renders in the canonical light-mode color (dark mode adapts to `#F87171` etc. on screen but stored SVG keeps `#DC2626`). Eraser removes intersected strokes. No custom-color UI exposed.
**Severity if fails:** High

### TC-INK-05: Highlighter opacity
**Preconditions:** Canvas open over a markdown spec.
**Steps:**
1. Pick highlighter, yellow color.
2. Drag over a line of body text.
**Expected result:** Stroke commits at opacity ~0.35 so the text remains legible underneath (per commit `a24584d`).
**Severity if fails:** High

### TC-INK-06: Undo/redo depth ≥ 50
**Preconditions:** Empty canvas.
**Steps:**
1. Draw 60 distinct strokes.
2. Tap Undo 50 times.
3. Tap Redo 50 times.
**Expected result:** After 50 undos, 10 strokes remain visible; additional undo is a no-op. Redo restores to the 60-stroke state.
**Severity if fails:** High

### TC-INK-07: Rapid undo/redo does not double-commit
**Preconditions:** Canvas with 10 strokes.
**Steps:**
1. Rapidly alternate Undo/Redo at finger-speed for ~10 s.
**Expected result:** Visible stroke count is always in {0..10} and converges to the last explicit state. No phantom strokes or duplicates appear in the SVG after exit.
**Severity if fails:** Medium

### TC-INK-08: Shape primitives (line, arrow, rect, circle)
**Preconditions:** Canvas open.
**Steps:**
1. For each of line, arrow, rect, circle tools: drag from point A to point B.
**Expected result:** Correct primitive drawn; arrow has a head; rect and circle are axis-aligned on the drag; all commit one stroke-group each.
**Severity if fails:** Medium

### TC-INK-09: Anchor persistence across scroll
**Preconditions:** Long markdown spec; canvas open.
**Steps:**
1. Draw a stroke near line 20.
2. Scroll down 500 px.
3. Scroll back.
**Expected result:** Stroke stays pinned to the same content location (same paragraph/line) — not to a viewport offset.
**Severity if fails:** High

---

## 8. Review panel (typed Q&A auto-load, auto-save, submit)

### TC-REV-01: Open Questions auto-extracted into cards
**Preconditions:** `02-spec.md` contains `## Open Questions` with `### Q1:` and `### Q2:` under it.
**Steps:**
1. Navigate to Review Panel from the Spec Reader or Annotation Canvas.
**Expected result:** One typed-answer card per Q heading. Cards show the exact question text. (See REG-BUG-3.)
**Severity if fails:** Critical

### TC-REV-02: Auto-save every 5 s
**Preconditions:** Review Panel open; at least one Q card.
**Steps:**
1. Type an answer.
2. Wait 6 s.
3. Kill the app (`adb shell am force-stop …`).
4. Relaunch, re-open the same job's Review Panel.
**Expected result:** Typed answer recovered from the local draft (`<appdocs>/drafts/<job-id>/03-review.md.draft`). No data loss.
**Severity if fails:** Critical

### TC-REV-03: Free-form notes field
**Preconditions:** Review Panel open.
**Steps:**
1. Type a multiline note into the free-form field.
2. Trigger auto-save, kill app, relaunch.
**Expected result:** Note persisted and rerendered with line breaks intact.
**Severity if fails:** High

### TC-REV-04: Live annotation summary
**Preconditions:** Canvas had 3 strokes committed before navigating to Review Panel.
**Steps:**
1. Open Review Panel.
**Expected result:** Markdown pane shows the real spec plus a "3 strokes across N groups" (or equivalent) annotation summary. Not a hardcoded "Auth flow — TOTP rollout". (See REG-BUG-3.)
**Severity if fails:** Critical

### TC-REV-05: Back-nav preserves in-memory state
**Preconditions:** Review Panel open with typed content.
**Steps:**
1. Tap back to Spec Reader.
2. Re-open Review Panel within the same session.
**Expected result:** Typed answers still present in the cards (state not thrown away on route pop within session).
**Severity if fails:** Medium

---

## 9. Submit confirmation (planned writes preview, commit, cancel, offline warning)

### TC-SUB-01: Planned-writes preview
**Preconditions:** Review Panel populated; tapped Submit Review.
**Steps:**
1. Observe the Submit Confirmation dialog.
**Expected result:** Dialog lists planned `FileWrite`s: `03-review.md`, `03-annotations.svg`, `03-annotations.png` (markdown) OR per-page `03-annotations-p{n}.{svg,png}` (PDF), plus changelog append path. Commit message preview reads `review: <job-id>`.
**Severity if fails:** High

### TC-SUB-02: Submit & commit happy path
**Preconditions:** Submit Confirmation open.
**Steps:**
1. Tap "Submit & commit".
**Expected result:** Dialog closes; a SnackBar toasts "Review committed" (or similar); Job List phase chip flips from `spec` to `review`; unpushed-commit badge increments. (See REG-BUG-4.)
**Severity if fails:** Critical

### TC-SUB-03: Cancel closes the dialog
**Preconditions:** Submit Confirmation open.
**Steps:**
1. Tap "Cancel".
**Expected result:** Dialog closes with no commit. No SnackBar. Draft + in-memory review state unchanged. (See REG-BUG-4.)
**Severity if fails:** High

### TC-SUB-04: Offline warning
**Preconditions:** Airplane mode on before the submit dialog opens.
**Steps:**
1. Open Submit Confirmation.
**Expected result:** A banner or notice clarifies the commit is local-only and will push on next Sync Up (FR-1.27). Submit still allowed.
**Severity if fails:** Medium

### TC-SUB-05: Commit failure surfaces
**Preconditions:** Induce a failure (e.g. simulated disk-full or corrupt `.git` — see TC-SYNC-04).
**Steps:**
1. Tap Submit & commit.
**Expected result:** Dialog closes with a failure SnackBar ("Commit failed — see logs"); no half-written files; `03-review.md` not present unless the full commit landed.
**Severity if fails:** Critical

---

## 10. Approve confirmation

### TC-APR-01: Approve disabled until phase = revised
**Preconditions:** Job in phase `spec` (no `03-review.md`).
**Steps:**
1. Open the job; look for Approve affordance.
**Expected result:** Approve is disabled or hidden. Tooltip/explainer references FR-1.26.
**Severity if fails:** High

### TC-APR-02: Approve commits `05-approved` atomically
**Preconditions:** Job in phase `revised`.
**Steps:**
1. Tap Approve.
2. Confirm in the Approval Confirmation dialog.
**Expected result:** Exactly one commit lands on local `claude-jobs` containing: empty `05-approved` file + changelog line "Approved — ready for implementation." Commit message `approve: <job-id>`. Phase chip updates to `approved`.
**Severity if fails:** Critical

### TC-APR-03: Approve cancel
**Preconditions:** Approval Confirmation dialog open.
**Steps:**
1. Tap Cancel.
**Expected result:** Dialog closes; no commit; phase chip unchanged.
**Severity if fails:** High

---

## 11. Conflict archived flow

### TC-CONF-01: Sync Up rejected → archive + reset
**Preconditions:** Local `claude-jobs` has 2 unpushed commits. From a second device (or by pushing from the desktop), push a 3rd commit to `origin/claude-jobs` so branches diverge.
**Steps:**
1. Tap Sync Up.
**Expected result:** Push rejected; the app runs `ConflictResolver.archiveAndReset`; Conflict Archived screen shows the on-device backup path (`files/backups/<repo>/<branch>-<ts>/`). Local HEAD now equals `origin/claude-jobs` after a subsequent merge of `origin/main`.
**Severity if fails:** Critical

### TC-CONF-02: Backup contents are complete
**Preconditions:** TC-CONF-01 just ran.
**Steps:**
1. `adb shell run-as … ls files/backups/<repo>/<branch>-*/jobs/pending/<id>/`.
**Expected result:** Every file from the local `jobs/pending/<id>/` directory at pre-reset HEAD is present in the backup.
**Severity if fails:** Critical

### TC-CONF-03: Sync Down while local is dirty
**Preconditions:** An uncommitted change is present in the workdir (e.g. by crashing mid-submit).
**Steps:**
1. Tap Sync Down.
**Expected result:** Dialog "You have unsaved changes. Commit or discard?" — no fetch runs. Choosing Discard cleans the tree; retrying Sync Down proceeds.
**Severity if fails:** High

---

## 12. Settings

### TC-SET-01: Account section
**Preconditions:** Signed in.
**Steps:**
1. Open Settings.
**Expected result:** ACCOUNT section shows `name`, `email` from GitHub `/user`, and a Sign out action. No token is shown in plaintext.
**Severity if fails:** Medium

### TC-SET-02: Repository section
**Preconditions:** Settings open.
**Steps:**
1. Read the REPOSITORY section.
**Expected result:** Current repo name + default branch + last Sync Down timestamp are visible. "Switch repo" action routes to Repo Picker.
**Severity if fails:** Medium

### TC-SET-03: Export backups via Storage Access Framework
**Preconditions:** At least one backup folder exists (e.g. from TC-CONF-01).
**Steps:**
1. Tap "Export backups".
2. Pick a destination folder in the SAF picker.
**Expected result:** Recursive copy completes; destination contains the entire backup tree. `ExportOutcome.success` toasted. Source in app-private storage untouched.
**Severity if fails:** High

### TC-SET-04: Theme quick-toggle persists
**Preconditions:** App in system-default theme.
**Steps:**
1. Toggle to dark from Settings (or the Job List quick toggle).
2. Kill and relaunch the app.
**Expected result:** App relaunches in dark regardless of system setting. Toggling back to "system" makes it respect Android UI mode again (FR-1.40, FR-1.41).
**Severity if fails:** Medium

---

## 13. Sync status bar

### TC-SYNC-01: Sync Down happy path
**Preconditions:** Online; no new remote commits.
**Steps:**
1. Tap Sync Down.
**Expected result:** Status bar progress goes `Started → Fetching → Complete`; toast "Up to date" (or equivalent). No-op for main merge into claude-jobs.
**Severity if fails:** High

### TC-SYNC-02: Sync Down pulls new `main` into `claude-jobs`
**Preconditions:** `origin/main` has new commits since the last Sync Down.
**Steps:**
1. Tap Sync Down.
**Expected result:** Local `main` fast-forwarded; merge commit into `claude-jobs` lands; new files visible under the workdir when browsing through the FS adapter (D-13).
**Severity if fails:** Critical

### TC-SYNC-03: Sync Up happy path
**Preconditions:** 1+ local unpushed commit; online.
**Steps:**
1. Tap Sync Up.
**Expected result:** Progress → Complete within <10 s p90 on LTE (NFR-10); unpushed-commit badge clears.
**Severity if fails:** Critical

### TC-SYNC-04: Sync Up with corrupt `.git`
**Preconditions:** Deliberately corrupt the repo's `.git/HEAD` via `adb shell run-as …`.
**Steps:**
1. Tap Sync Up.
**Expected result:** Typed error surfaces verbatim with a "Run `git fsck`" hint; app does not crash; other repos unaffected.
**Severity if fails:** High

---

## 14. Cross-cutting

### TC-CC-01: SafeArea on every pushed route
**Preconditions:** Signed in.
**Steps:**
1. Navigate through: SignIn → RepoPicker → JobList → SpecReader (md) → AnnotationCanvas → ReviewPanel → SubmitConfirmation → back to JobList → Settings → ChangelogViewer → SpecReader (PDF) → New Spec Author (if enabled).
2. At each screen, screenshot and check for status-bar overlap.
**Expected result:** No screen paints content under the Android status bar. (See REG-BUG-1.)
**Severity if fails:** Critical

### TC-CC-02: Orientation lock (landscape)
**Preconditions:** Any screen.
**Steps:**
1. Rotate the tablet to portrait.
**Expected result:** App stays in landscape (orientation locked). Android does not re-layout into portrait.
**Severity if fails:** Medium

### TC-CC-03: Offline read loop
**Preconditions:** Sync Down completed, then airplane mode on.
**Steps:**
1. Open a cached job.
2. Annotate.
3. Type review answers.
4. Tap Submit Review.
5. Tap Approve (if in revised phase).
**Expected result:** All of the above succeed locally. Sync Down / Up explicitly fail ("offline"). Unpushed badge reflects accumulated commits.
**Severity if fails:** Critical

### TC-CC-04: Cold start to JobList < 2 s (NFR-2)
**Preconditions:** Last-opened job was a real-mode JobList. Wi-Fi on. App killed.
**Steps:**
1. Launch the app icon; start a stopwatch.
2. Stop when the JobList first paints its rows.
3. `adb logcat | grep gitmdscribe.nfr2` for the 3 checkpoint marks.
**Expected result:** Elapsed wall-clock ≤ 2 s (Wi-Fi) or ≤ 3 s (offline). Three `ColdStartTracker` checkpoints logged.
**Severity if fails:** High

---

## 15. Regression tests for the four fixes in commit 766d813

These tests guard against the specific bugs reported and fixed on 2026-04-21. They must stay in the suite permanently.

### REG-BUG-1: Status bar no longer overlaps pushed routes
**Bug:** Routes pushed after the root (SpecReader, AnnotationCanvas, ReviewPanel, Settings, …) painted under the Android status bar because SafeArea was applied only at `_AuthGate` and not at `MaterialApp.builder`.
**Preconditions:** Signed in; JobList visible.
**Steps:**
1. Tap a job → Spec Reader opens.
2. Tap Annotate → Annotation Canvas opens.
3. Tap Review Panel affordance → Review Panel opens.
4. From Review Panel, tap Submit → Submit Confirmation dialog overlays.
5. Return to JobList and open Settings.
6. Open ChangelogViewer.
7. Screenshot each of the above.
**Expected result:** In every screenshot, the app bar / top-chrome starts below the status bar. No icon, text, or touch target is occluded by the status bar. The fix is at `MaterialApp.builder`, so every subtree inherits the inset.
**Severity if fails:** Critical

### REG-BUG-2: Annotate panel renders the full spec markdown
**Bug:** `annotation_canvas/markdown_stub.dart` rendered a hardcoded two-section extract ("Open questions + Assumptions"). Strokes could only anchor to that stub, not the real content.
**Preconditions:** A job whose `02-spec.md` has headings beyond "Open Questions" and "Assumptions" — for example a `## Goals`, `## Non-Goals`, and a fenced code block, plus a `## File-Level Change Plan`.
**Steps:**
1. Open the job.
2. Tap Annotate.
3. Scroll the underlying markdown behind the canvas.
4. Draw a stroke over the `## Goals` heading.
5. Draw another stroke over the fenced code block.
6. Draw a third over `## File-Level Change Plan`.
7. Toggle `drawingEnabled` off (view mode) and scroll; toggle on and try to draw again.
**Expected result:**
- The full spec is visible behind the ink layer — all five+ headings, the code block, any table or list in the spec, not just a hardcoded two-section extract.
- All three strokes commit with anchors pointing to their respective lines (verifiable in the `03-annotations.svg` after Submit Review: `data-anchor-line` values differ for each and correspond to the real markdown).
- In view mode (`drawingEnabled=false`) `IgnorePointer` lets scroll gestures fall through; no ink is captured; strokes resume in draw mode.
**Severity if fails:** Critical

### REG-BUG-3: Review screen left pane shows real spec + typed Q&A cards
**Bug:** `review_panel/markdown_pane.dart` rendered a hardcoded "Auth flow — TOTP rollout" body. `ReviewPanelScreen` passed an empty `questions` list, so typed Q&A cards never appeared; only the "Free-form notes" field rendered.
**Preconditions:** A job whose `02-spec.md` is clearly named something *other* than "Auth flow — TOTP rollout" (e.g. "Payments — invoice redesign") and whose `## Open Questions` section contains at least `### Q1:` and `### Q2:`.
**Steps:**
1. Open the job; draw 2 strokes on the canvas.
2. Navigate to Review Panel.
3. Observe the left pane content.
4. Observe the right pane typed-Q&A card list.
5. Type an answer into Q1, wait 6 s for auto-save, kill and relaunch, re-open.
**Expected result:**
- Left pane renders "Payments — invoice redesign" (or whatever the real spec contains) — NOT the old hardcoded "Auth flow — TOTP rollout" body.
- Left pane also shows a live annotation summary reflecting the 2 strokes drawn.
- Right pane shows a Q1 card and a Q2 card auto-extracted from `## Open Questions`, plus the Free-form notes field.
- After relaunch, the Q1 answer is preserved (proves `OpenQuestionExtractor` + autosave are both wired, not just the card UI).
**Severity if fails:** Critical

### REG-BUG-4: Submit Review dialog closes with feedback; Cancel closes with no commit
**Bug:** The "Submit & commit" button in `SubmitConfirmationScreen` appeared to do nothing — no close, no toast. The Cancel button lacked an `onPressed`. All three call sites (review_panel, annotation_canvas, spec_reader_md, spec_reader_pdf) awaited a submission that never arrived.
**Preconditions:** A job in phase `spec` with at least one typed answer and one stroke on the canvas.
**Steps:**
1. From Review Panel, tap Submit Review → Submit Confirmation opens.
2. Tap "Submit & commit".
3. Observe the dialog and the underlying screen.
4. Re-open the job (now in phase `review`); re-open the Submit Confirmation (or Approve flow) — for coverage, trigger Submit from `annotation_canvas`, then `spec_reader_md`, then `spec_reader_pdf` in separate jobs.
5. Re-open a submit dialog on another job; tap Cancel.
**Expected result:**
- After tapping Submit & commit: the dialog closes within ~1 s; a SnackBar toasts a concrete success ("Review committed: review: <job-id>") or a concrete failure — never silence.
- The returned `ReviewSubmission` value drives the SnackBar — every call site (`review_panel`, `annotation_canvas`, `spec_reader_md`, `spec_reader_pdf`) awaits it and surfaces feedback.
- Tapping Cancel closes the dialog immediately, with no SnackBar, no commit, no file writes. Draft state is untouched.
- Rapid double-tap on Submit does not produce two commits (idempotent until dialog close).
**Severity if fails:** Critical

---

## 16. Sign-off checklist

One line per test case; QA ticks the box after a clean pass.

| TC ID | Title | Pass |
|---|---|---|
| TC-AUTH-01 | Fresh install routes to Sign In | [ ] |
| TC-AUTH-02 | Device Flow happy path (real mode) | [ ] |
| TC-AUTH-03 | Device Flow mockup-mode stub | [ ] |
| TC-AUTH-04 | PAT fallback — valid token | [ ] |
| TC-AUTH-05 | PAT fallback — invalid token | [ ] |
| TC-AUTH-06 | Revoked-token recovery | [ ] |
| TC-AUTH-07 | Sign out clears token + last-session keys | [ ] |
| TC-REPO-01 | List repos the user has access to | [ ] |
| TC-REPO-02 | Search / filter | [ ] |
| TC-REPO-03 | Pick a repo → Job List | [ ] |
| TC-REPO-04 | Last-opened shortcut | [ ] |
| TC-REPO-05 | Non-default branch repo | [ ] |
| TC-JOBS-01 | Lists folders under jobs/pending/ | [ ] |
| TC-JOBS-02 | Phase chip truth table | [ ] |
| TC-JOBS-03 | Tap row → opens correct Spec Reader | [ ] |
| TC-JOBS-04 | Unpushed-commit badge | [ ] |
| TC-JOBS-05 | Changelog viewer from Job List | [ ] |
| TC-JOBS-06 | Empty-state (no jobs yet) | [ ] |
| TC-MD-01 | Renders CommonMark + GFM | [ ] |
| TC-MD-02 | Heading nav rail + sticky section header | [ ] |
| TC-MD-03 | Typography — ~40 chars/line | [ ] |
| TC-MD-04 | Dark-mode readability | [ ] |
| TC-MD-05 | Missing spec file (corrupt job folder) | [ ] |
| TC-PDF-01 | Page-by-page render + fit-to-width | [ ] |
| TC-PDF-02 | Pinch-zoom | [ ] |
| TC-PDF-03 | Scroll FPS on a large PDF | [ ] |
| TC-PDF-04 | Render-error fallback | [ ] |
| TC-INK-01 | Stylus draws, finger does not (palm rejection) | [ ] |
| TC-INK-02 | Pressure sensitivity visible | [ ] |
| TC-INK-03 | Latency budget (NFR-1 <25 ms) | [ ] |
| TC-INK-04 | All 6 ink colors + eraser | [ ] |
| TC-INK-05 | Highlighter opacity | [ ] |
| TC-INK-06 | Undo/redo depth ≥ 50 | [ ] |
| TC-INK-07 | Rapid undo/redo does not double-commit | [ ] |
| TC-INK-08 | Shape primitives (line, arrow, rect, circle) | [ ] |
| TC-INK-09 | Anchor persistence across scroll | [ ] |
| TC-REV-01 | Open Questions auto-extracted into cards | [ ] |
| TC-REV-02 | Auto-save every 5 s | [ ] |
| TC-REV-03 | Free-form notes field | [ ] |
| TC-REV-04 | Live annotation summary | [ ] |
| TC-REV-05 | Back-nav preserves in-memory state | [ ] |
| TC-SUB-01 | Planned-writes preview | [ ] |
| TC-SUB-02 | Submit & commit happy path | [ ] |
| TC-SUB-03 | Cancel closes the dialog | [ ] |
| TC-SUB-04 | Offline warning | [ ] |
| TC-SUB-05 | Commit failure surfaces | [ ] |
| TC-APR-01 | Approve disabled until phase = revised | [ ] |
| TC-APR-02 | Approve commits 05-approved atomically | [ ] |
| TC-APR-03 | Approve cancel | [ ] |
| TC-CONF-01 | Sync Up rejected → archive + reset | [ ] |
| TC-CONF-02 | Backup contents are complete | [ ] |
| TC-CONF-03 | Sync Down while local is dirty | [ ] |
| TC-SET-01 | Account section | [ ] |
| TC-SET-02 | Repository section | [ ] |
| TC-SET-03 | Export backups via Storage Access Framework | [ ] |
| TC-SET-04 | Theme quick-toggle persists | [ ] |
| TC-SYNC-01 | Sync Down happy path | [ ] |
| TC-SYNC-02 | Sync Down pulls new main into claude-jobs | [ ] |
| TC-SYNC-03 | Sync Up happy path | [ ] |
| TC-SYNC-04 | Sync Up with corrupt .git | [ ] |
| TC-CC-01 | SafeArea on every pushed route | [ ] |
| TC-CC-02 | Orientation lock (landscape) | [ ] |
| TC-CC-03 | Offline read loop | [ ] |
| TC-CC-04 | Cold start to JobList < 2 s (NFR-2) | [ ] |
| REG-BUG-1 | Status bar no longer overlaps pushed routes | [ ] |
| REG-BUG-2 | Annotate panel renders the full spec markdown | [ ] |
| REG-BUG-3 | Review screen left pane shows real spec + typed Q&A cards | [ ] |
| REG-BUG-4 | Submit Review dialog closes with feedback; Cancel closes with no commit | [ ] |

---

*End of manual test-case spec. 68 test cases total. Keep regression tests REG-BUG-1 through REG-BUG-4 in perpetuity.*
