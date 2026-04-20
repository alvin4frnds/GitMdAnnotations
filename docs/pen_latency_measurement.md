# Pen-latency measurement protocol (NFR-1)

Companion to [IMPLEMENTATION.md](IMPLEMENTATION.md) §2.4 (threading) and
§4.5 (annotation module), and [PRD/TabletApp-PRD.md](PRD/TabletApp-PRD.md)
§7 (**NFR-1: pen latency < 25 ms p95 on Pad Go 2**).

This doc defines the Milestone 1b close-out gate for NFR-1. It does **not**
define how to write pen-handling code — that's §4.5. It defines how to
*measure* the latency budget we committed to, what the numbers mean, and
where the measurement is a lower bound vs. real-world hardware.

---

## Hardware assumptions

| Property            | Value                                              |
|---------------------|----------------------------------------------------|
| Device              | OnePlus Pad Go 2 (model `OPD2504`)                 |
| ADB device id       | `NBB6BMB6QGQWLFV4`                                 |
| OS                  | Android 16, arm64                                  |
| Display             | 11.6", 2800 × 2000, 90 Hz                          |
| Frame period        | ~11.11 ms                                          |
| Stylus              | OnePlus active stylus (pressure-sensitive)         |

The 90 Hz frame period is the single most important number here. Any
latency figure that looks "too good" (say, p50 under 1 ms) is almost
certainly a test-infrastructure artifact where the callback collapsed
inside a single frame — see "Known limitations" below.

---

## Test invocation

Run the M1b close-out measurement against the tablet:

```bash
fvm flutter test integration_test/pen_latency_test.dart -d NBB6BMB6QGQWLFV4
```

Before running, unskip the `group(..., skip: ...)` wrapper in
[`integration_test/pen_latency_test.dart`](../integration_test/pen_latency_test.dart).
The skip is intentional for PR-time runs (no device connected).

The harness prints `[pen-latency] p50=…us p95=…us p99=…us samples=…`
on every run, then asserts `p95 < 25 ms`. Treat the console line as the
authoritative record — copy it into the M1b close-out PROGRESS entry.

For a quick host-VM overhead check (dispatch plumbing only, no paint
pipeline), the PR-gate regression pin is:

```bash
fvm flutter test test/ui/widgets/ink_overlay/ink_overlay_latency_test.dart
```

---

## What "latency" means here

The harness installs a `WidgetsBinding.instance.addPostFrameCallback`
immediately before each `PointerMoveEvent` it dispatches. The callback
fires on the next scheduled frame — the first frame that can include
the new stroke point. A `Stopwatch` started at the same instant as the
dispatch is stopped inside the callback.

So **latency** here is:

> wall-clock between `PointerMoveEvent` dispatch and the first frame
> that paints the committed sample.

That covers Flutter's event-dispatch, `InkOverlay` widget routing,
`PointerEventMapper` translation, the controller/session mutation,
`ValueNotifier` notification, and the `InkOverlayPainter` raster. It
does **not** cover the stylus driver, digitizer sampling, or compositor
latency — those live below the Flutter engine and `flutter_test`'s
`TestGesture` bypasses them (see "Known limitations").

### Why this is still a useful gate

NFR-1's budget sits in the Flutter pipeline because the driver /
digitizer stack on the Pad Go 2 is a fixed-cost external. If Flutter's
piece fits under 25 ms p95, the end-to-end budget has head-room for the
external delta. If Flutter alone already violates the budget, the app
fails the NFR regardless of hardware — that's the actionable signal
this test catches.

---

## Expected numbers (90 Hz)

| Percentile | Expected     | Sanity range                            |
|------------|--------------|-----------------------------------------|
| p50        | ~6 ms        | 2–8 ms (sub-frame jitter from pump cadence) |
| p95        | ~17 ms       | 11–22 ms (one to two frame periods)     |
| p99        | ≤ 22 ms      | up to 25 ms before it's a test failure  |

Heuristics:

- **p50 under 1 ms.** The test is measuring synchronous collapse,
  not frame latency. Increase the idle between moves (currently 11 ms
  to match 90 Hz) or confirm the post-frame callback is actually firing
  on a later vsync.
- **p95 above 25 ms.** NFR-1 violation. Before assuming a regression,
  verify the device is plugged in, the app is a release build, and no
  background work (libgit2 fetch, PNG flatten) is running on the same
  isolate. If still red, follow the fallback in IMPLEMENTATION.md §8.3
  — drop `InkOverlay` to an `AndroidView` embedding a native canvas.

---

## Known limitations — what we are NOT measuring

1. **Synthetic-event gap.** `integration_test` uses `TestGesture` to
   synthesize `PointerEvent`s straight into the binding. There is no
   driver roundtrip, no digitizer-to-kernel jitter, and no HAL queue.
   The measured p95 is therefore a **lower bound** on real-world ink
   latency; the actual NFR budget is exercised only when a human is
   drawing on the tablet with the stylus.
2. **No pressure variation.** The test script keeps pressure at the
   default (`1.0`) across the stroke. Real pressure modulation may
   trigger a different code path in any future "pressure-adaptive
   stroke width" implementation; re-measure if §4.5 grows that branch.
3. **Single-device characterization.** The 25 ms budget is specific to
   the Pad Go 2 (PRD §7). Running the test on an emulator, a different
   Android tablet, or a desktop target is valid for CI-on-device smoke
   but does **not** produce an NFR-1 signal.
4. **Frame-boundary coarseness.** At 90 Hz our quantum is ~11 ms. Two
   samples that really differ by 0.5 ms can land in the same frame
   bucket. The statistics are fair in aggregate (60+ samples) but no
   single latency number below one frame is meaningful in isolation.

**Full end-to-end latency**, including driver + digitizer, requires
manual high-speed-camera observation: record the stylus tip and the
screen at ≥240 fps, count frames from contact to ink. That workflow is
out of scope for T11 and tracked in [Issues.md](Issues.md) under the
"camera-observation follow-up" entry.

---

## Maintenance

- **When `InkOverlay` or the annotation pipeline changes**, re-run
  both tests (host regression pin + on-device NFR gate) before closing
  the task. The host pin lands on every PR; the on-device gate is
  milestone-close-out only.
- **When the tablet OS or display hardware changes** (e.g. a firmware
  update that switches the panel to 120 Hz), update the "Expected
  numbers" table and revisit the `Duration(milliseconds: 11)` idle in
  the integration test.
- **When the Flutter channel changes**, re-characterize p50/p95/p99
  once — Flutter's scheduler has shifted frame-boundary semantics
  across releases before.
