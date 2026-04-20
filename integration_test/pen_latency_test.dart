@Tags(['platform'])
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitmdannotations_tablet/app/providers/annotation_providers.dart';
import 'package:gitmdannotations_tablet/domain/entities/job_ref.dart';
import 'package:gitmdannotations_tablet/domain/entities/repo_ref.dart';
import 'package:gitmdannotations_tablet/infra/clock/system_clock.dart';
import 'package:gitmdannotations_tablet/infra/id/system_id_generator.dart';
import 'package:gitmdannotations_tablet/ui/screens/annotation_canvas/annotation_canvas_screen.dart';
import 'package:integration_test/integration_test.dart';

/// NFR-1 gate: pen latency must stay under **25 ms p95** on the OPD2504
/// (OnePlus Pad Go 2, 90 Hz) — PRD §7, IMPLEMENTATION.md §2.4 + §4.5.
///
/// This file is the M1b close-out harness. It drives a scripted stylus
/// stroke through the real `AnnotationCanvasScreen` (composition-root
/// overrides point at `SystemClock` + `SystemIdGenerator`, identical to
/// `bootstrap.dart`) and, for each `PointerMoveEvent`, records the wall
/// clock from the event's `timeStamp` until the first frame that paints
/// the newly-committed sample.
///
/// **Scope.** This measures Flutter's *paint pipeline* latency — pointer
/// event landing in the framework → `onSample` → `ValueNotifier` update
/// → `InkOverlayPainter` repaint → frame rasterized. It does **not**
/// include the stylus-driver and digitizer overhead upstream of the
/// Flutter engine; `flutter_test`'s `TestGesture` synthesizes
/// `PointerEvent`s directly on the binding, bypassing the kernel. That
/// delta vs real stylus contact is the camera-observation follow-up
/// tracked in `docs/Issues.md`. The numbers here are a **lower bound**
/// on real-world ink latency.
///
/// **Invocation.**
/// ```
/// fvm flutter test integration_test/pen_latency_test.dart \
///   -d NBB6BMB6QGQWLFV4
/// ```
/// Target hardware: OPD2504 (device id `NBB6BMB6QGQWLFV4`, Android 16,
/// arm64, 90 Hz display). On non-target devices the p95 assertion is
/// not meaningful — the test still runs but ship/interpret results only
/// on Pad Go 2.
///
/// **Expected envelope** (90 Hz, ~11 ms/frame):
///   - p50 ≈ 6 ms (half-frame average)
///   - p95 ≈ 17 ms (one full frame + dispatch slack)
///   - p99 ≤ 22 ms
///
/// If p95 ≥ 25 ms, investigate per IMPLEMENTATION.md §8.3 fallback:
/// drop `InkOverlay` to an `AndroidView` embedding a native canvas.
///
/// The body is **skipped by default** — matches the M1a/M1b integration
/// precedent (see `integration_test/infra/pdf/pdfx_adapter_test.dart`
/// and `integration_test/infra/git/git_adapter_test.dart`). Un-skip at
/// M1b close-out on the real tablet.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('pen latency NFR-1 gate (OPD2504)', () {
    testWidgets('p95 ink lag < 25 ms on a 60-point stylus stroke',
        (tester) async {
      final samples = <Duration>[];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            clockProvider.overrideWithValue(SystemClock()),
            idGeneratorProvider.overrideWithValue(SystemIdGenerator()),
          ],
          child: MaterialApp(
            home: AnnotationCanvasScreen(
              jobRef: JobRef(
                repo: const RepoRef(owner: 'demo', name: 'payments-api'),
                jobId: 'spec-auth-flow-totp',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Record wall-clock between a PointerMove and the first frame that
      // paints after. We install a post-frame callback before each move
      // and latch the delta when it fires. The binding guarantees
      // post-frame callbacks fire on the first frame containing the
      // committed work — which, for `InkOverlay`, is the frame that
      // rasterizes the new sample via `InkOverlayPainter`.
      final canvasCenter =
          tester.getCenter(find.byType(AnnotationCanvasScreen));
      final gesture = await tester.startGesture(
        canvasCenter,
        kind: PointerDeviceKind.stylus,
      );
      await tester.pump();

      for (var i = 0; i < 60; i++) {
        final sw = Stopwatch()..start();
        WidgetsBinding.instance.addPostFrameCallback((Duration _) {
          sw.stop();
          samples.add(sw.elapsed);
        });
        await gesture.moveBy(const Offset(1, 0));
        await tester.pump(); // Force the frame the callback waits for.
        // Small idle between moves so we sample across frame boundaries
        // rather than collapsing the burst under one frame.
        await tester.pump(const Duration(milliseconds: 11)); // 90 Hz tick.
      }

      await gesture.up();
      await tester.pumpAndSettle();

      expect(samples.length, greaterThanOrEqualTo(30),
          reason: 'need >=30 samples for a meaningful p95');

      samples.sort();
      final p50 = samples[(samples.length * 0.50).floor()];
      final p95 = samples[(samples.length * 0.95).floor()];
      final p99 = samples[(samples.length * 0.99).floor()];

      // Console print is captured by `flutter test -d <id>` output; the
      // M1b close-out protocol expects these logged alongside the
      // assertion so the team has raw numbers even on failure.
      // ignore: avoid_print
      print('[pen-latency] p50=${p50.inMicroseconds}us '
          'p95=${p95.inMicroseconds}us p99=${p99.inMicroseconds}us '
          'samples=${samples.length}');

      expect(
        p95,
        lessThan(const Duration(milliseconds: 25)),
        reason:
            'NFR-1 violation: pen latency p95 must be <25 ms on Pad Go 2',
      );
    });
  }, skip: 'TODO(M1b-close): run on OPD2504 device for NFR-1 verification');
}
