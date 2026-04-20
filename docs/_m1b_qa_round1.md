# M1b QA Round 1

Independent visual QA on OPD2504 (device `NBB6BMB6QGQWLFV4`, Android 16, 2800x1980 landscape) via ADB. Mockup mode, clean install. Walked the full mockup browser (13 entries) and exercised the new M1b surfaces: Annotation canvas (screen 5) and Spec reader PDF (screen 4b). No crashes observed. Logcat clean throughout. One Medium finding on the PDF mockup surface (actual rendering diverges from the brief's "transparent placeholder" expectation — produces visible "Failed to render page N" error boxes instead). Three Low finds (unwired chrome affordances, display-only page rail, single-tile PDF layout). All M1a regression screens render cleanly in both light and dark themes.

## Screenshots

All paths below are relative to `docs/_m1b_qa_round1/`.

| # | File | Description |
|---|------|-------------|
| 01 | `01-initial.png` | Launch state: Sign in selected, left rail shows all 13 mockup entries (1-12 with 4b inserted between 4 and 5). |
| 02 | `02-sync-down.png` | Screen 2 — Sync Down progress panel. Clean. |
| 03 | `03-job-list.png` | Screen 3 — job list. Shows 3 jobs including the new `spec-invoice-pdf-redesign` (awaiting review, `.pdf` tag). |
| 04 | `04-spec-reader-md.png` | Screen 4 — Spec reader (markdown). Outline rail + rendered spec. |
| 05 | `05-spec-reader-pdf.png` | Screen 4b (NEW) — Spec reader (PDF). Top chrome (pen bar, undo/redo, Review panel, Submit Review), Pages rail (Page 1/2/3), main area shows one page tile tinted red with "Failed to render page 1" text. |
| 06 | `06-pdf-scrolled.png` | PDF after attempted vertical swipe in main area — unchanged (InkOverlay swallows touches per §T9 stylus-only policy). |
| 07 | `07-pdf-page2.png` | After tapping "Page 2" in the Pages rail — unchanged, Page 1 still highlighted. Rail items are display-only (no onTap handler). |
| 08 | `08-annotation-canvas.png` | Screen 5 — Annotation canvas. Top chrome present (pen tools, undo, redo, Review panel, Submit Review). Left rail shows "On this page" outline + "Ink layers" seeded list. Main content shows rendered markdown stub; no hardcoded strokes, no margin notes. |
| 09 | `09-undo-tapped.png` | Canvas after tapping Undo on empty state — no crash, no visual change. |
| 10 | `10-finger-swipe.png` | Canvas after attempting a finger swipe over the markdown — palm rejection works; no stroke rendered. |
| 11 | `11-submit-tapped.png` | Canvas after tapping "Submit Review" — no crash; no navigation (unwired, expected). |
| 12 | `12-review-panel-tap.png` | Canvas after tapping "Review panel →" link — no crash; no navigation (unwired, expected). |
| 13 | `13-eraser-tap.png` | Canvas after tapping the erase-all icon — no crash, no visual state to clear. |
| 14 | `14-review-panel.png` | Screen 6 — Review panel. Clean. |
| 15 | `15-submit-confirmation.png` | Screen 7 — Submit confirmation dialog. Clean. |
| 16 | `16-sync-up.png` | Screen 8 — Sync Up progress panel. Clean. |
| 17 | `17-changelog-viewer.png` | Screen 9 — Changelog viewer. Clean. |
| 18 | `18-approval-confirmation.png` | Screen 10 — Approval confirmation dialog. Clean. |
| 19 | `19-conflict-archived.png` | Screen 11 — Conflict archived dialog. Clean. |
| 20 | `20-new-spec.png` | Screen 12 — New spec author (Phase 2). Clean. |
| 21 | `21-pdf-tap-page.png` | Tap on PDF page body — no crash (stylus-only; finger produces nothing). |
| 23 | `23-theme-toggle.png` | Annotation canvas in dark mode. Theme toggle works; markdown, chrome, ink-layer list render correctly. |
| 24 | `24-pdf-dark.png` | Spec reader PDF in dark mode. Same "Failed to render page 1" error; error box background renders dark-red on near-black. |
| 25 | `25-canvas-final.png` | Annotation canvas back in light mode — unchanged from screenshot 08. |
| 26 | `26-sign-in.png` | Sign-in screen revisited. Clean. |

## Findings

### Critical
None.

### High
None.

### Medium

- **M1 — Spec reader (PDF, screen 4b) shows "Failed to render page 1" error box in mockup mode.** The brief states the PDF pages should appear "nearly-transparent" because `FakePdfRasterPort.renderPage` returns the 8-byte PNG signature. In practice those 8 bytes are not a decodable PNG (no IHDR/IDAT/IEND), so `Image.memory`'s `errorBuilder` fires and `PdfPageTile._ErrorBox` renders a red-tinted box with literal text "Failed to render page $n". This is the dominant visual on screen 4b in both light and dark themes — a visitor browsing the mockups will reasonably read it as a broken screen rather than "placeholder content". See `lib/ui/widgets/pdf_page_view/pdf_page_tile.dart:48,70-80` and `lib/domain/fakes/fake_pdf_raster_port.dart:108-109`. Consider either (a) seeding the mockup registry with a tiny valid transparent PNG override (`pagePngs:` in bootstrap's `register(...)`), or (b) silencing the error box when the decoded bytes round-trip through the signature-only fake. Screenshots: `05-spec-reader-pdf.png`, `06-pdf-scrolled.png`, `07-pdf-page2.png`, `24-pdf-dark.png`.

### Low

- **L1 — PDF pages rail is display-only.** Tapping "Page 2" or "Page 3" in the Pages rail produces no effect; the file (`spec_reader_pdf_rail.dart`) has no `GestureDetector`/`InkWell` on items. The markdown equivalent (`spec_reader_md`) has the same pattern of jump-on-tap outline items in the mockup, so users will likely expect the Pages rail to jump-scroll. The rail comment ("the viewer can scrollspy-highlight as the user pages through") acknowledges this is explicitly display-only for M1b, but the affordance is visually identical to a clickable nav list — consider styling or adding `MouseCursor.defer`/`SystemMouseCursors.basic` so it doesn't read as interactive, or wiring a `ScrollController.animateTo` callback. Screenshot: `07-pdf-page2.png`.

- **L2 — PDF pane vertical scrolling is inaccessible in mockup browsing.** The `InkOverlay` sits full-stack with `HitTestBehavior.opaque` and swallows finger swipes that would otherwise drive the underlying `ListView`/`InteractiveViewer`. The pane's own comment calls this out ("an acceptable tradeoff for T9 stylus-only; pen/pan toggle queued"). On a real device with a stylus this won't block pan/zoom, but in mockup browsing (finger only) the viewer is effectively stuck on Page 1's first screenful. Noted for QA awareness; flagged as Low because it matches the documented design. Screenshot: `06-pdf-scrolled.png`.

- **L3 — PDF aspect ratio (1.4142, A4 portrait) produces tiles taller than viewport.** On 2800x1980 with a 200px page rail and 240px mockup rail, each tile is ~1860w x ~2630h logical — taller than the ~1860px visible height — so only the top of Page 1 ever appears, with the "Failed to render" text floating mid-viewport. Combined with L2, screen 4b visually reads as one large tinted rectangle. Again, matches the documented default aspect; if L2 is deferred, consider shrinking the default `pageAspectRatio` or adding a visible page-count chip. Screenshot: `05-spec-reader-pdf.png`.

## Notable observations (not findings)

- **Annotation canvas hardcoded-content removal verified.** No strokes are rendered in the initial state of screen 5 (confirming `_InkOverlayPainter` hardcoded strokes are gone), and no "TOTP first…" or "match refresh token" margin-note chrome appears in the main content (confirming removal per T7). Screenshot: `08-annotation-canvas.png`.

- **Annotation canvas "Ink layers" rail is still hardcoded to `Group A — line 47 / B — line 23 / C — line 89`.** This is display-only chrome by design (see `left_rail.dart` line 8: "display-only, seeded with the three mockup groups"), not state-driven. Worth noting that the content is cosmetic — a real reviewer would not see these entries reflect their actual ink state. If this was intended to be live in M1b, it's a missed wire-up; if not, fine.

- **Palm rejection confirmed.** Finger swipes on the canvas and finger taps on the PDF pane create no strokes and do not crash. Real stylus behavior (creating live strokes) cannot be verified via ADB and is deferred to manual device QA.

- **Submit Review / Review panel → links on the annotation canvas chrome are unwired** (tapping does nothing). Brief acknowledged this. No crash.

- **Dark mode works across all M1b surfaces.** Annotation canvas and Spec reader PDF render cleanly when the theme toggle is flipped to dark. Pen-color swatches correctly swap the black swatch to white in dark mode. Screenshots: `23-theme-toggle.png`, `24-pdf-dark.png`.

- **Job list correctly surfaces the new `spec-invoice-pdf-redesign` job** (`.pdf` file tag, "Awaiting review" pill) alongside the existing `spec-auth-flow-totp` and `spec-webhook-retry-policy` entries — matches the seeded mockup filesystem changes for T9.

- **Logcat clean.** No exceptions, errors, or warnings from the Flutter engine or Dart side across the entire walk-through. Only benign OS framework logs (DynamicFramerate, IJankManager, AutofillManager).

- **All M1a screens (sign-in, sync-down, job-list, spec-reader-md, review panel, submit confirmation, sync-up, changelog, approval confirmation, conflict archived, new-spec) render without visual regression.**
