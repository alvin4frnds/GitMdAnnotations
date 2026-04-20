import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitmdannotations_tablet/domain/entities/pointer_sample.dart';
import 'package:gitmdannotations_tablet/domain/entities/stroke_group.dart';
import 'package:gitmdannotations_tablet/ui/widgets/ink_overlay/ink_overlay.dart';

typedef _Reported = ({InkPointerPhase phase, PointerSample sample});

Widget _host({
  required List<_Reported> sink,
  DateTime Function()? nowProvider,
  ValueNotifier<List<Offset>>? active,
  List<StrokeGroup> groups = const [],
  Size size = const Size(800, 600),
}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox.fromSize(
          size: size,
          child: InkOverlay(
            groups: groups,
            activeStroke: active ?? ValueNotifier<List<Offset>>(const []),
            currentStrokeColor: const Color(0xFFDC2626),
            currentStrokeWidth: 2.1,
            onSample: (phase, sample) =>
                sink.add((phase: phase, sample: sample)),
            nowProvider: nowProvider ?? () => DateTime.utc(2026, 4, 20),
            hitTestBehavior: HitTestBehavior.opaque,
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('stylus pointer-down invokes onSample(down, ...) once',
      (tester) async {
    final sink = <_Reported>[];
    await tester.pumpWidget(_host(sink: sink));

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(InkOverlay)),
      kind: PointerDeviceKind.stylus,
    );
    await tester.pump();

    expect(sink, hasLength(1));
    expect(sink.single.phase, InkPointerPhase.down);
    expect(sink.single.sample.kind, PointerKind.stylus);

    await gesture.up();
    await tester.pump();
  });

  testWidgets('stylus pointer-move invokes onSample(move, ...)',
      (tester) async {
    final sink = <_Reported>[];
    await tester.pumpWidget(_host(sink: sink));

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(InkOverlay)),
      kind: PointerDeviceKind.stylus,
    );
    await tester.pump();
    await gesture.moveBy(const Offset(10, 10));
    await tester.pump();

    expect(sink.map((r) => r.phase).toList(), [
      InkPointerPhase.down,
      InkPointerPhase.move,
    ]);

    await gesture.up();
    await tester.pump();
  });

  testWidgets('stylus pointer-up invokes onSample(up, ...)', (tester) async {
    final sink = <_Reported>[];
    await tester.pumpWidget(_host(sink: sink));

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(InkOverlay)),
      kind: PointerDeviceKind.stylus,
    );
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(sink.map((r) => r.phase).toList(), [
      InkPointerPhase.down,
      InkPointerPhase.up,
    ]);
  });

  testWidgets('down -> move -> up fires in expected phase order',
      (tester) async {
    final sink = <_Reported>[];
    await tester.pumpWidget(_host(sink: sink));

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(InkOverlay)),
      kind: PointerDeviceKind.stylus,
    );
    await tester.pump();
    await gesture.moveBy(const Offset(5, 5));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(sink.map((r) => r.phase).toList(), [
      InkPointerPhase.down,
      InkPointerPhase.move,
      InkPointerPhase.up,
    ]);
  });

  testWidgets('touch pointer reports its kind faithfully (no rejection)',
      (tester) async {
    final sink = <_Reported>[];
    await tester.pumpWidget(_host(sink: sink));

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(InkOverlay)),
      // default kind is touch
    );
    await tester.pump();

    expect(sink, hasLength(1));
    expect(sink.single.phase, InkPointerPhase.down);
    expect(sink.single.sample.kind, PointerKind.touch);

    await gesture.up();
    await tester.pump();
  });

  testWidgets('pressure from custom PointerDownEvent reaches callback',
      (tester) async {
    // `TestGesture.down` / `startGesture` in Flutter 3.41.7 do not accept a
    // `pressure` parameter. We construct a custom PointerDownEvent directly
    // and push it through `downWithCustomEvent`, which is the documented
    // seam for pressure/tilt tests.
    final sink = <_Reported>[];
    await tester.pumpWidget(_host(sink: sink));

    final center = tester.getCenter(find.byType(InkOverlay));
    final gesture = await tester.createGesture(kind: PointerDeviceKind.stylus);
    final downEvent = PointerDownEvent(
      position: center,
      kind: PointerDeviceKind.stylus,
      pressure: 0.6,
    );
    await gesture.downWithCustomEvent(center, downEvent);
    await tester.pump();

    expect(sink, hasLength(1));
    expect(sink.single.sample.pressure, closeTo(0.6, 1e-9));

    await gesture.up();
    await tester.pump();
  });

  testWidgets('nowProvider is called per sample', (tester) async {
    final sink = <_Reported>[];
    var counter = 0;
    DateTime tick() {
      counter += 1;
      return DateTime.utc(2026, 4, 20).add(Duration(milliseconds: counter));
    }

    await tester.pumpWidget(_host(sink: sink, nowProvider: tick));

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(InkOverlay)),
      kind: PointerDeviceKind.stylus,
    );
    await tester.pump();
    await gesture.moveBy(const Offset(5, 5));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    final timestamps = sink.map((r) => r.sample.timestamp).toList();
    expect(timestamps, hasLength(3));
    expect(timestamps[1].isAfter(timestamps[0]), isTrue);
    expect(timestamps[2].isAfter(timestamps[1]), isTrue);
  });

  testWidgets('cancel fires onSample(cancel, ...)', (tester) async {
    // A pointer-cancel is most easily simulated by crafting one and
    // routing it through the binding — the widget must still observe it.
    final sink = <_Reported>[];
    await tester.pumpWidget(_host(sink: sink));

    final center = tester.getCenter(find.byType(InkOverlay));
    final gesture = await tester.startGesture(
      center,
      kind: PointerDeviceKind.stylus,
    );
    await tester.pump();

    await gesture.cancel();
    await tester.pump();

    expect(sink.map((r) => r.phase).toList(), [
      InkPointerPhase.down,
      InkPointerPhase.cancel,
    ]);
  });
}
