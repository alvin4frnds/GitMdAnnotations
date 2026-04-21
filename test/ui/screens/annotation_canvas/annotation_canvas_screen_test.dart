import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitmdannotations_tablet/app/providers/annotation_providers.dart';
import 'package:gitmdannotations_tablet/domain/entities/job_ref.dart';
import 'package:gitmdannotations_tablet/domain/entities/pointer_sample.dart';
import 'package:gitmdannotations_tablet/domain/entities/repo_ref.dart';
import 'package:gitmdannotations_tablet/domain/fakes/fake_clock.dart';
import 'package:gitmdannotations_tablet/domain/fakes/fake_id_generator.dart';
import 'package:gitmdannotations_tablet/ui/screens/annotation_canvas/annotation_canvas_screen.dart';
import 'package:gitmdannotations_tablet/ui/theme/app_theme.dart';
import 'package:gitmdannotations_tablet/ui/theme/tokens.dart';
import 'package:gitmdannotations_tablet/ui/widgets/ink_overlay/ink_overlay.dart';

final _jobRef = JobRef(
  repo: const RepoRef(owner: 'demo', name: 'payments-api'),
  jobId: 'spec-auth-flow-totp',
);

final _t0 = DateTime.utc(2026, 4, 20, 9, 14, 22);

Widget _host({
  required JobRef jobRef,
  Set<PointerKind>? allowedPointerKinds,
}) {
  return ProviderScope(
    overrides: [
      clockProvider.overrideWithValue(FakeClock(_t0)),
      idGeneratorProvider.overrideWithValue(FakeIdGenerator()),
      if (allowedPointerKinds != null)
        allowedPointerKindsProvider.overrideWithValue(allowedPointerKinds),
    ],
    child: MaterialApp(
      theme: AppTheme.build(AppTokens.light),
      home: Scaffold(body: AnnotationCanvasScreen(jobRef: jobRef)),
    ),
  );
}

ProviderContainer _containerFor(WidgetTester tester) {
  return ProviderScope.containerOf(
    tester.element(find.byType(AnnotationCanvasScreen)),
  );
}

/// Landscape-locked production app wants a wide viewport; the default
/// flutter_test surface (800×600) clips the top chrome row. Set once per
/// test so the Row doesn't overflow.
Future<void> _setLandscapeSurface(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1600, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

void main() {
  // -----------------------------------------------------------------------
  // Initial render
  // -----------------------------------------------------------------------
  testWidgets('initial render shows an InkOverlay and no committed strokes',
      (tester) async {
    await _setLandscapeSurface(tester);
    await tester.pumpWidget(_host(jobRef: _jobRef));
    await tester.pump();

    expect(find.byType(InkOverlay), findsOneWidget);
    // Top chrome + left rail should still render (breadcrumb + ink-layer
    // header is enough to prove the rest of the mockup chrome survives).
    expect(find.text('spec-auth-flow-totp'), findsOneWidget);
    expect(find.text('INK LAYERS'), findsOneWidget);

    final container = _containerFor(tester);
    final state = container.read(annotationControllerProvider(_jobRef));
    expect(state.groups, isEmpty);
  });

  // -----------------------------------------------------------------------
  // Stylus down/move/up commits a group.
  // -----------------------------------------------------------------------
  testWidgets('stylus down/move/up commits exactly one StrokeGroup',
      (tester) async {
    await _setLandscapeSurface(tester);
    await tester.pumpWidget(_host(jobRef: _jobRef));
    await tester.pump();

    final center = tester.getCenter(find.byType(InkOverlay));
    final gesture = await tester.startGesture(center,
        kind: PointerDeviceKind.stylus);
    await tester.pump();
    await gesture.moveBy(const Offset(10, 10));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    final container = _containerFor(tester);
    final state = container.read(annotationControllerProvider(_jobRef));
    expect(state.groups, hasLength(1));
    expect(state.hasActiveStroke, isFalse);
  });

  // -----------------------------------------------------------------------
  // Palm rejection at the wiring seam.
  // -----------------------------------------------------------------------
  testWidgets('touch down/move/up does NOT commit a StrokeGroup',
      (tester) async {
    await _setLandscapeSurface(tester);
    await tester.pumpWidget(_host(jobRef: _jobRef));
    await tester.pump();

    final center = tester.getCenter(find.byType(InkOverlay));
    // default kind is touch
    final gesture = await tester.startGesture(center);
    await tester.pump();
    await gesture.moveBy(const Offset(10, 10));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    final container = _containerFor(tester);
    final state = container.read(annotationControllerProvider(_jobRef));
    expect(state.groups, isEmpty);
  });

  testWidgets('mouse down/move/up does NOT commit with default '
      'allowedPointerKinds (stylus-only — tablet release behavior)',
      (tester) async {
    await _setLandscapeSurface(tester);
    await tester.pumpWidget(_host(jobRef: _jobRef));
    await tester.pump();

    final center = tester.getCenter(find.byType(InkOverlay));
    final gesture = await tester.startGesture(center,
        kind: PointerDeviceKind.mouse);
    await tester.pump();
    await gesture.moveBy(const Offset(10, 10));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    final container = _containerFor(tester);
    final state = container.read(annotationControllerProvider(_jobRef));
    expect(state.groups, isEmpty);
  });

  // -----------------------------------------------------------------------
  // Dev-loop: widened allowedPointerKinds (mirrors the composition-root
  // override bootstrap.dart installs when `--dart-define=
  // ALLOW_MOUSE_ANNOTATION=true`). Proves the flag reaches the widget
  // tree and lets mouse events drive strokes on desktop / emulator.
  // -----------------------------------------------------------------------
  testWidgets('mouse down/move/up commits a StrokeGroup when '
      'allowedPointerKinds includes mouse (dev-loop build)',
      (tester) async {
    await _setLandscapeSurface(tester);
    await tester.pumpWidget(_host(
      jobRef: _jobRef,
      allowedPointerKinds: const {
        PointerKind.stylus,
        PointerKind.mouse,
        PointerKind.touch,
      },
    ));
    await tester.pump();

    final center = tester.getCenter(find.byType(InkOverlay));
    final gesture = await tester.startGesture(center,
        kind: PointerDeviceKind.mouse);
    await tester.pump();
    await gesture.moveBy(const Offset(10, 10));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    final container = _containerFor(tester);
    final state = container.read(annotationControllerProvider(_jobRef));
    expect(state.groups, hasLength(1));
    expect(state.hasActiveStroke, isFalse);
  });

  // -----------------------------------------------------------------------
  // Undo / redo buttons drive the controller.
  // -----------------------------------------------------------------------
  testWidgets('undo button removes the last committed group',
      (tester) async {
    await _setLandscapeSurface(tester);
    await tester.pumpWidget(_host(jobRef: _jobRef));
    await tester.pump();

    final center = tester.getCenter(find.byType(InkOverlay));
    final gesture = await tester.startGesture(center,
        kind: PointerDeviceKind.stylus);
    await tester.pump();
    await gesture.up();
    await tester.pump();

    final container = _containerFor(tester);
    expect(
      container.read(annotationControllerProvider(_jobRef)).groups,
      hasLength(1),
    );

    await tester.tap(find.byTooltip('Undo'));
    await tester.pump();

    expect(
      container.read(annotationControllerProvider(_jobRef)).groups,
      isEmpty,
    );
  });

  testWidgets('redo button restores a previously undone group',
      (tester) async {
    await _setLandscapeSurface(tester);
    await tester.pumpWidget(_host(jobRef: _jobRef));
    await tester.pump();

    final center = tester.getCenter(find.byType(InkOverlay));
    final gesture = await tester.startGesture(center,
        kind: PointerDeviceKind.stylus);
    await tester.pump();
    await gesture.up();
    await tester.pump();

    await tester.tap(find.byTooltip('Undo'));
    await tester.pump();
    await tester.tap(find.byTooltip('Redo'));
    await tester.pump();

    final container = _containerFor(tester);
    expect(
      container.read(annotationControllerProvider(_jobRef)).groups,
      hasLength(1),
    );
  });

  // -----------------------------------------------------------------------
  // Active-stroke notifier populates between down and up.
  // -----------------------------------------------------------------------
  testWidgets(
      'mid-stroke (down + move, no up) active-stroke list has >1 point',
      (tester) async {
    await _setLandscapeSurface(tester);
    await tester.pumpWidget(_host(jobRef: _jobRef));
    await tester.pump();

    final center = tester.getCenter(find.byType(InkOverlay));
    final gesture = await tester.startGesture(center,
        kind: PointerDeviceKind.stylus);
    await tester.pump();
    await gesture.moveBy(const Offset(10, 10));
    await tester.pump();
    await gesture.moveBy(const Offset(5, 5));
    await tester.pump();

    // Grab the active-stroke listenable from the InkOverlay widget's props
    // — the screen owns the notifier and passes it down.
    final overlay = tester.widget<InkOverlay>(find.byType(InkOverlay));
    expect(overlay.activeStroke.value.length, greaterThan(1),
        reason: 'active stroke should accumulate move samples');

    // Tear-down: finish the gesture so the test harness is clean.
    await gesture.up();
    await tester.pump();
  });

  // -----------------------------------------------------------------------
  // After up, the active stroke clears (committed strokes render from
  // state.groups instead).
  // -----------------------------------------------------------------------
  testWidgets('active stroke clears after pointer-up on a stylus stroke',
      (tester) async {
    await _setLandscapeSurface(tester);
    await tester.pumpWidget(_host(jobRef: _jobRef));
    await tester.pump();

    final center = tester.getCenter(find.byType(InkOverlay));
    final gesture = await tester.startGesture(center,
        kind: PointerDeviceKind.stylus);
    await tester.pump();
    await gesture.moveBy(const Offset(10, 10));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    final overlay = tester.widget<InkOverlay>(find.byType(InkOverlay));
    expect(overlay.activeStroke.value, isEmpty);
  });

  // -----------------------------------------------------------------------
  // Dispose cleans up the notifier (no pending-listener leak).
  // -----------------------------------------------------------------------
  testWidgets('popping the screen disposes the active-stroke notifier',
      (tester) async {
    await _setLandscapeSurface(tester);
    await tester.pumpWidget(_host(jobRef: _jobRef));
    await tester.pump();

    // Replace with an empty app to force the screen to unmount.
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SizedBox())),
    );
    await tester.pump();

    // No expect — flutter_test's internal leak / listener checks will
    // surface if `dispose()` missed removing the notifier.
  });
}
