import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitmdannotations_tablet/domain/entities/pointer_sample.dart';
import 'package:gitmdannotations_tablet/ui/widgets/ink_overlay/ink_overlay.dart';

/// Host-side regression pin for T11. This file is **not** the NFR-1
/// measurement — paint-pipeline latency on real hardware lives in
/// `integration_test/pen_latency_test.dart`. Here we measure only the
/// overhead of `InkOverlay`'s pointer-event → `PointerSample` → `onSample`
/// dispatch plumbing so a refactor of the mapper or `Listener` wrapping
/// can't silently blow the per-sample CPU budget.
///
/// Why pin this cheaply:
/// - At 90 Hz the Pad Go 2 emits a new frame every ~11 ms, and we target
///   p95 ink latency <25 ms (NFR-1 / PRD §7). Anything that spends >1 ms
///   per sample in dispatch eats into that budget before paint even runs.
/// - The host VM is faster than the tablet CPU, so an average <1 ms per
///   sample here is a lower-bound guarantee, not a device guarantee.
/// - `DateTime.now()` is the cheapest clock available in pure Dart; the
///   resolution (~1 ms on Windows) is fine for a 100-sample batch average.
void main() {
  testWidgets(
      'InkOverlay invokes onSample exactly 100 times for a 100-point stylus '
      'stroke', (tester) async {
    final samples = <PointerSample>[];
    await tester.pumpWidget(_hostOverlay(onSample: (_, s) => samples.add(s)));

    await _drive100PointStroke(tester);

    expect(samples, hasLength(100));
  });

  testWidgets(
      'InkOverlay dispatch+callback overhead averages below 1 ms per sample',
      (tester) async {
    final count = _DispatchCounter();
    await tester.pumpWidget(_hostOverlay(onSample: (_, _) => count.tick()));

    final sw = Stopwatch()..start();
    await _drive100PointStroke(tester);
    sw.stop();

    expect(count.value, 100);
    // Wall-clock includes `tester.pump()` overhead too, which is fine:
    // we're pinning that the *whole* round-trip stays cheap, not just
    // `_dispatch`. Budget is intentionally loose (100 ms for 100 samples
    // = 1 ms/sample) — if this pins tighter later, great, but a looser
    // bound is enough to catch an O(n) → O(n^2) regression in the mapper.
    expect(sw.elapsedMilliseconds, lessThan(100),
        reason:
            '100 dispatches should complete in <100 ms on host VM; got '
            '${sw.elapsedMilliseconds} ms');
  });
}

/// Drives a 100-point stylus stroke: one down, 98 moves (each +1 px right),
/// one up. Uses `moveBy` so the gesture's position advances monotonically
/// and every move generates a distinct `PointerMoveEvent`.
Future<void> _drive100PointStroke(WidgetTester tester) async {
  final center = tester.getCenter(find.byType(InkOverlay));
  final gesture = await tester.startGesture(
    center,
    kind: PointerDeviceKind.stylus,
  );
  await tester.pump();
  for (var i = 0; i < 98; i++) {
    await gesture.moveBy(const Offset(1, 0));
  }
  await tester.pump();
  await gesture.up();
  await tester.pump();
}

Widget _hostOverlay({
  required void Function(InkPointerPhase, PointerSample) onSample,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 800,
          height: 600,
          child: InkOverlay(
            groups: const [],
            activeStroke: ValueNotifier<List<Offset>>(const []),
            currentStrokeColor: const Color(0xFFDC2626),
            currentStrokeWidth: 2.1,
            onSample: onSample,
            nowProvider: () => DateTime.utc(2026, 4, 20),
            hitTestBehavior: HitTestBehavior.opaque,
          ),
        ),
      ),
    ),
  );
}

/// Tiny counter so the timing test doesn't pay the cost of `List.add`
/// on every sample — we only care about raw dispatch overhead.
class _DispatchCounter {
  int value = 0;
  void tick() => value += 1;
}
