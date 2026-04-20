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

  testWidgets(
      'PointerSample.x/y are LOCAL to the overlay, not global screen coords',
      (tester) async {
    // Pins the mapper's choice of `event.localPosition` over
    // `event.position`. Without this, swapping local→global would silently
    // offset every stroke by the overlay's on-screen origin in T7.
    //
    // Layout: InkOverlay is offset by (200, 100) from screen origin via a
    // Padding wrapper. A tap at the global Offset(205, 107) lands 5px
    // right / 7px down from the overlay's top-left corner; the reported
    // PointerSample must reflect the LOCAL (5, 7), not the global values.
    final sink = <_Reported>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: 200, top: 100),
              child: SizedBox(
                width: 400,
                height: 300,
                child: InkOverlay(
                  groups: const [],
                  activeStroke: ValueNotifier<List<Offset>>(const []),
                  currentStrokeColor: const Color(0xFFDC2626),
                  currentStrokeWidth: 2.1,
                  onSample: (phase, sample) =>
                      sink.add((phase: phase, sample: sample)),
                  nowProvider: () => DateTime.utc(2026, 4, 20),
                  hitTestBehavior: HitTestBehavior.opaque,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    // Sanity: the overlay really is offset where we expect.
    final topLeft = tester.getTopLeft(find.byType(InkOverlay));
    expect(topLeft, const Offset(200, 100));

    final gesture = await tester.startGesture(
      const Offset(205, 107),
      kind: PointerDeviceKind.stylus,
    );
    await tester.pump();

    expect(sink, hasLength(1));
    expect(sink.single.phase, InkPointerPhase.down);
    expect(sink.single.sample.x, closeTo(5.0, 1e-6));
    expect(sink.single.sample.y, closeTo(7.0, 1e-6));

    await gesture.up();
    await tester.pump();
  });
}
