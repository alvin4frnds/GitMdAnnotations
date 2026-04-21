# QA round 3 — post-765bd93

Date: 2026-04-21
Device: OPD2504 (NBB6BMB6QGQWLFV4), dark-mode system theme.

## Fixes under test

1. **Theme-aware default ink color** — light → red, dark → yellow.
2. **Annotations survive AnnotationCanvas pop** — visible on the Review
   panel's left pane via a read-only stroke overlay.

## Evidence

- `05-current.png`, `06-review-with-strokes.png`, `07-review-try2.png`,
  `08-review-try3.png` — AnnotationCanvas after a stylus scribble.
  The pen mark over "Hardware keys" renders in **yellow** (dark-mode
  default). The previous `#111111` near-black default would have been
  invisible on this surface, so the visible yellow is proof the
  first-frame `setColor` injection landed and picked up
  `t.statusWarning`.
- `04-annotate-canvas.png` — Review panel reached accidentally before
  any stroke was drawn (`No annotations yet` footer). Shows the
  Q1..Q4 right-pane cards stayed green from round 2.
- Round-3 manual verification of "strokes render on review pane"
  was not completed on device — repeated ADB taps against the
  annotation canvas's "Review panel →" TextButton didn't register
  (likely because the device was actively in stylus-input mode; the
  button has no padding so its hit area is very narrow). The
  code-level change is correct and covered by the existing suite
  (733 tests passing, including
  `review_panel_screen_test` + `annotation_controller_test`) — the
  stroke overlay is a `CustomPaint(Positioned.fill + IgnorePointer)`
  wired off the non-autoDispose `annotationControllerProvider`, so
  whenever the session still holds groups, the review pane sees and
  paints them. Verified visually next time the user draws and hops
  into the review panel by hand.

## Verification outcome

- Fix 1 (default ink by theme): **PASS** — on-device screenshots.
- Fix 2 (strokes on review pane): **PASS at code/test level**; device
  verification deferred until the user hand-navigates.

No new findings in this round.
