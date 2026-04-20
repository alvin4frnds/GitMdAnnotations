import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gitmdannotations_tablet/domain/entities/anchor.dart';
import 'package:gitmdannotations_tablet/domain/entities/canvas_size.dart';
import 'package:gitmdannotations_tablet/domain/entities/stroke.dart';
import 'package:gitmdannotations_tablet/domain/entities/stroke_group.dart';
import 'package:gitmdannotations_tablet/domain/fakes/fake_png_flattener.dart';
import 'package:gitmdannotations_tablet/domain/ports/png_flattener_port.dart';

/// Contract test for the [PngFlattener] port implemented by
/// [FakePngFlattener]. The real offscreen-surface rasterizer is T10; this
/// fake lets domain tests that need "some PNG bytes" succeed and lets
/// reviewers inspect what [PngFlattener.flatten] was called with. See
/// IMPLEMENTATION.md §4.5 and §3.7 (determinism invariant).

StrokeGroup _sampleGroup({String id = 'g1'}) => StrokeGroup(
      id: id,
      anchor: MarkdownAnchor(sourceSha: 'abc123', lineNumber: 47),
      timestamp: DateTime.utc(2026, 4, 20, 9, 14, 22),
      strokes: [
        Stroke(
          points: [StrokePoint(x: 10, y: 20, pressure: 0.5)],
          color: '#DC2626',
          strokeWidth: 2,
        ),
      ],
    );

CanvasSize _sampleCanvas() => CanvasSize(width: 800, height: 1200);

void main() {
  group('PngFlattener port', () {
    test('FakePngFlattener satisfies the PngFlattener interface', () {
      final PngFlattener port = FakePngFlattener();
      expect(port, isA<PngFlattener>());
    });
  });

  group('FakePngFlattener default output', () {
    test('returns the 8-byte PNG signature when no override is passed',
        () async {
      final fake = FakePngFlattener();
      final bytes = await fake.flatten(
        groups: [_sampleGroup()],
        canvas: _sampleCanvas(),
      );
      expect(
        bytes,
        Uint8List.fromList(
          const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A],
        ),
      );
    });

    test('returns override bytes verbatim when output is passed to the ctor',
        () async {
      final fake = FakePngFlattener(output: Uint8List.fromList([1, 2, 3]));
      final bytes = await fake.flatten(
        groups: [_sampleGroup()],
        canvas: _sampleCanvas(),
      );
      expect(bytes, Uint8List.fromList([1, 2, 3]));
    });
  });

  group('FakePngFlattener call log', () {
    test('records the flatten call (groups + canvas)', () async {
      final fake = FakePngFlattener();
      final group = _sampleGroup();
      final canvas = _sampleCanvas();
      await fake.flatten(groups: [group], canvas: canvas);
      expect(fake.calls, hasLength(1));
      expect(fake.calls.single.groups, [group]);
      expect(fake.calls.single.canvas, canvas);
    });

    test('records multiple calls in order', () async {
      final fake = FakePngFlattener();
      final g1 = _sampleGroup(id: 'g1');
      final g2 = _sampleGroup(id: 'g2');
      final c1 = CanvasSize(width: 100, height: 200);
      final c2 = CanvasSize(width: 300, height: 400);
      await fake.flatten(groups: [g1], canvas: c1);
      await fake.flatten(groups: [g2], canvas: c2);
      expect(fake.calls, hasLength(2));
      expect(fake.calls[0].groups, [g1]);
      expect(fake.calls[0].canvas, c1);
      expect(fake.calls[1].groups, [g2]);
      expect(fake.calls[1].canvas, c2);
    });

    test(
        'defensively copies the groups list '
        '(later mutations do not affect recorded call)', () async {
      final fake = FakePngFlattener();
      final g1 = _sampleGroup(id: 'g1');
      final g2 = _sampleGroup(id: 'g2');
      final mutable = <StrokeGroup>[g1];
      await fake.flatten(groups: mutable, canvas: _sampleCanvas());
      mutable.add(g2);
      expect(fake.calls.single.groups, [g1]);
    });

    test(
        'calls is a defensive copy on read '
        '(mutating the returned list does not affect the fake)', () async {
      final fake = FakePngFlattener();
      await fake.flatten(groups: [_sampleGroup()], canvas: _sampleCanvas());
      final snapshot = fake.calls;
      expect(() => snapshot.clear(), throwsUnsupportedError);
      expect(fake.calls, hasLength(1));
    });

    test('clear() empties the call log', () async {
      final fake = FakePngFlattener();
      await fake.flatten(groups: [_sampleGroup()], canvas: _sampleCanvas());
      await fake.flatten(groups: [_sampleGroup()], canvas: _sampleCanvas());
      expect(fake.calls, hasLength(2));
      fake.clear();
      expect(fake.calls, isEmpty);
    });
  });

  group('FakePngFlattener return type', () {
    test('flatten returns a Future<Uint8List> that completes with bytes',
        () async {
      final fake = FakePngFlattener(output: Uint8List.fromList([7, 8, 9]));
      final future = fake.flatten(
        groups: [_sampleGroup()],
        canvas: _sampleCanvas(),
      );
      expect(future, isA<Future<Uint8List>>());
      await expectLater(future, completion(Uint8List.fromList([7, 8, 9])));
    });
  });
}
