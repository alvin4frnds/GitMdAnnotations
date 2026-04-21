import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gitmdannotations_tablet/domain/entities/anchor.dart';
import 'package:gitmdannotations_tablet/domain/entities/stroke.dart';
import 'package:gitmdannotations_tablet/domain/entities/stroke_group.dart';
import 'package:gitmdannotations_tablet/domain/services/annotation_pdf_composer.dart';

/// 68-byte fully-valid 1×1 transparent grayscale+alpha PNG. Small
/// enough to embed in tests, valid enough for `pw.MemoryImage` to parse.
final _tinyPng = Uint8List.fromList(base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AA'
  'AAASUVORK5CYII=',
));

void main() {
  group('AnnotationPdfComposer', () {
    test('produces bytes with a %PDF- header', () async {
      final bytes = await const AnnotationPdfComposer().compose(
        backgroundPng: _tinyPng,
        canonicalWidth: 900,
        canonicalHeight: 1200,
        groups: const [],
      );
      expect(bytes.length, greaterThan(100));
      final header = String.fromCharCodes(bytes.sublist(0, 5));
      expect(header, '%PDF-');
    });

    test('embeds the trailing PDF EOF marker', () async {
      final bytes = await const AnnotationPdfComposer().compose(
        backgroundPng: _tinyPng,
        canonicalWidth: 900,
        canonicalHeight: 1200,
        groups: const [],
      );
      final tail = String.fromCharCodes(
        bytes.sublist(bytes.length - 6),
      );
      expect(tail.trim().endsWith('%%EOF'), isTrue, reason: tail);
    });

    test('adding strokes increases the output size (vectors are emitted)',
        () async {
      final empty = await const AnnotationPdfComposer().compose(
        backgroundPng: _tinyPng,
        canonicalWidth: 900,
        canonicalHeight: 1200,
        groups: const [],
      );
      final withStrokes = await const AnnotationPdfComposer().compose(
        backgroundPng: _tinyPng,
        canonicalWidth: 900,
        canonicalHeight: 1200,
        groups: [
          StrokeGroup(
            id: 'g1',
            anchor: MarkdownAnchor(lineNumber: 1, sourceSha: 'abc'),
            timestamp: DateTime.utc(2026, 4, 21),
            strokes: [
              for (var i = 0; i < 5; i++)
                Stroke(
                  points: List.generate(
                    20,
                    (j) => StrokePoint(
                      x: (i * 10 + j).toDouble(),
                      y: (i * 5 + j * 2).toDouble(),
                      pressure: 0.5,
                    ),
                  ),
                  color: '#DC2626',
                  strokeWidth: 2,
                  opacity: 0.9,
                ),
            ],
          ),
        ],
      );
      expect(withStrokes.length, greaterThan(empty.length));
    });

    test('tolerates a stroke with zero points (emits nothing, no crash)',
        () async {
      final bytes = await const AnnotationPdfComposer().compose(
        backgroundPng: _tinyPng,
        canonicalWidth: 900,
        canonicalHeight: 1200,
        groups: [
          StrokeGroup(
            id: 'g',
            anchor: MarkdownAnchor(lineNumber: 1, sourceSha: 'abc'),
            timestamp: DateTime.utc(2026, 4, 21),
            strokes: [
              Stroke(
                points: const [],
                color: '#000000',
                strokeWidth: 1,
              ),
            ],
          ),
        ],
      );
      final header = String.fromCharCodes(bytes.sublist(0, 5));
      expect(header, '%PDF-');
    });
  });
}
