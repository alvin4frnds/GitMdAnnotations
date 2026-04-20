import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitmdannotations_tablet/domain/entities/anchor.dart';
import 'package:gitmdannotations_tablet/domain/entities/canvas_size.dart';
import 'package:gitmdannotations_tablet/domain/entities/stroke.dart';
import 'package:gitmdannotations_tablet/domain/entities/stroke_group.dart';
import 'package:gitmdannotations_tablet/domain/ports/png_flattener_port.dart';
import 'package:gitmdannotations_tablet/infra/png/png_flattener_adapter.dart';

/// The T10 adapter exercises `dart:ui.Picture.toImage` which needs
/// `TestWidgetsFlutterBinding` — a bare `test` package binding does not
/// supply a GPU surface.
MarkdownAnchor _anchor() =>
    MarkdownAnchor(lineNumber: 47, sourceSha: 'a3f91c');

Stroke _stroke(
  List<Offset> pts, {
  String color = '#DC2626',
  double width = 2.0,
}) {
  return Stroke(
    points: pts
        .map((p) => StrokePoint(x: p.dx, y: p.dy, pressure: 0.5))
        .toList(growable: false),
    color: color,
    strokeWidth: width,
  );
}

StrokeGroup _group(List<Stroke> strokes, {String id = 'g1'}) {
  return StrokeGroup(
    id: id,
    anchor: _anchor(),
    timestamp: DateTime.utc(2026, 4, 20, 9, 14, 22),
    strokes: strokes,
  );
}

CanvasSize _size(double w, double h) => CanvasSize(width: w, height: h);

const List<int> _pngMagic = [
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
];

bool _startsWithPngMagic(Uint8List bytes) {
  if (bytes.length < _pngMagic.length) return false;
  for (var i = 0; i < _pngMagic.length; i++) {
    if (bytes[i] != _pngMagic[i]) return false;
  }
  return true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PngFlattenerAdapter (port assignability)', () {
    test('is assignable to PngFlattener', () {
      const PngFlattener flat = PngFlattenerAdapter();
      expect(flat, isA<PngFlattener>());
    });
  });

  group('PngFlattenerAdapter.flatten — PNG signature', () {
    test('empty canvas returns bytes starting with the 8-byte PNG signature',
        () async {
      const flattener = PngFlattenerAdapter();
      final bytes = await flattener.flatten(
        groups: const [],
        canvas: _size(100, 100),
      );
      expect(_startsWithPngMagic(bytes), isTrue,
          reason: 'expected PNG magic at head; got ${bytes.take(8).toList()}');
    });

    test('non-empty canvas (with a stroke) also starts with PNG magic',
        () async {
      const flattener = PngFlattenerAdapter();
      final bytes = await flattener.flatten(
        groups: [
          _group([
            _stroke(const [Offset(10, 10), Offset(90, 90)]),
          ]),
        ],
        canvas: _size(100, 100),
      );
      expect(_startsWithPngMagic(bytes), isTrue);
    });
  });

  group('PngFlattenerAdapter.flatten — visible content', () {
    test('a stroke produces strictly more bytes than the empty canvas',
        () async {
      const flattener = PngFlattenerAdapter();
      final emptyBytes = await flattener.flatten(
        groups: const [],
        canvas: _size(100, 100),
      );
      final strokeBytes = await flattener.flatten(
        groups: [
          _group([
            _stroke(const [Offset(10, 10), Offset(90, 90)]),
          ]),
        ],
        canvas: _size(100, 100),
      );
      expect(strokeBytes.length, greaterThan(emptyBytes.length));
    });

    test(
        'two different stroke contents produce different PNG bytes '
        '(render is content-sensitive)', () async {
      const flattener = PngFlattenerAdapter();
      final a = await flattener.flatten(
        groups: [
          _group([
            _stroke(const [Offset(10, 10), Offset(90, 90)]),
          ]),
        ],
        canvas: _size(100, 100),
      );
      final b = await flattener.flatten(
        groups: [
          _group([
            _stroke(const [Offset(20, 80), Offset(80, 20)]),
          ]),
        ],
        canvas: _size(100, 100),
      );
      expect(listEquals(a, b), isFalse);
    });
  });

  group('PngFlattenerAdapter.flatten — determinism (§3.7)', () {
    test(
        'same groups + same canvas → byte-identical bytes across two calls',
        () async {
      const flattener = PngFlattenerAdapter();
      final groups = [
        _group([
          _stroke(const [Offset(10, 10), Offset(50, 50), Offset(90, 30)]),
        ]),
      ];
      final a = await flattener.flatten(
        groups: groups,
        canvas: _size(100, 100),
      );
      final b = await flattener.flatten(
        groups: groups,
        canvas: _size(100, 100),
      );
      expect(listEquals(a, b), isTrue);
    });
  });

  group('PngFlattenerAdapter.flatten — stroke edge cases', () {
    test('empty stroke in a group produces the same bytes as if it were absent',
        () async {
      const flattener = PngFlattenerAdapter();
      final realStroke = _stroke(const [Offset(20, 20), Offset(80, 80)]);
      final bytesWithEmpty = await flattener.flatten(
        groups: [
          _group([_stroke(const []), realStroke]),
        ],
        canvas: _size(100, 100),
      );
      final bytesWithoutEmpty = await flattener.flatten(
        groups: [
          _group([realStroke]),
        ],
        canvas: _size(100, 100),
      );
      expect(listEquals(bytesWithEmpty, bytesWithoutEmpty), isTrue);
    });

    test('single-point stroke produces bytes distinct from zero-point stroke',
        () async {
      const flattener = PngFlattenerAdapter();
      final withDot = await flattener.flatten(
        groups: [
          _group([
            _stroke(const [Offset(50, 50)], width: 4.0),
          ]),
        ],
        canvas: _size(100, 100),
      );
      final withoutAnything = await flattener.flatten(
        groups: [
          _group([_stroke(const [])]),
        ],
        canvas: _size(100, 100),
      );
      expect(listEquals(withDot, withoutAnything), isFalse,
          reason: 'a filled dot must produce different pixels than a no-op');
    });
  });

  group('PngFlattenerAdapter.flatten — image dimensions honor canvas size',
      () {
    test('canvas (100x60) produces an image sized 100x60', () async {
      const flattener = PngFlattenerAdapter();
      final bytes = await flattener.flatten(
        groups: const [],
        canvas: _size(100, 60),
      );
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final img = frame.image;
      expect(img.width, 100);
      expect(img.height, 60);
      img.dispose();
      codec.dispose();
    });

    test('canvas (123x45) produces an image sized 123x45', () async {
      const flattener = PngFlattenerAdapter();
      final bytes = await flattener.flatten(
        groups: const [],
        canvas: _size(123, 45),
      );
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final img = frame.image;
      expect(img.width, 123);
      expect(img.height, 45);
      img.dispose();
      codec.dispose();
    });
  });
}
