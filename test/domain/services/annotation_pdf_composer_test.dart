import 'dart:convert';
import 'dart:io' show ZLibCodec;
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

    test(
        'bottom-of-page stroke serializes with PDF-y near 0 (Y-flip correct)',
        () async {
      // Canonical coords: top=0, Y grows down. PDF: bottom=0, Y grows up.
      // A stroke at canonical (100, canonicalHeight-10) = near the BOTTOM of
      // the page in canonical space should flip to PDF y ≈ 10 (near the
      // BOTTOM of the PDF page in PDF-native coords). If Y flipping breaks
      // in the composer, the stroke lands on the wrong side of the page.
      const canonicalHeight = 12000.0;
      final bytes = await const AnnotationPdfComposer().compose(
        backgroundPng: _tinyPng,
        canonicalWidth: 900,
        canonicalHeight: canonicalHeight,
        groups: [
          StrokeGroup(
            id: 'bottom',
            anchor: MarkdownAnchor(lineNumber: 1, sourceSha: 'abc'),
            timestamp: DateTime.utc(2026, 4, 21),
            strokes: [
              Stroke(
                points: [
                  StrokePoint(
                    x: 100,
                    y: canonicalHeight - 10,
                    pressure: 0.5,
                  ),
                  StrokePoint(
                    x: 200,
                    y: canonicalHeight - 10,
                    pressure: 0.5,
                  ),
                ],
                color: '#DC2626',
                strokeWidth: 2,
              ),
            ],
          ),
        ],
      );
      // Scan raw bytes for `<x> <y> m` / `<x> <y> l` ops. Content streams
      // in the `pdf` package default to DEFLATE-compressed, so we look at
      // the raw bytes and search inside the FlateDecoded segment. Fast
      // path: use `dart:io`-free inflater via the dart:zlib-ish `ZLibCodec`.
      final stream = _decompressContentStream(bytes);
      final moveTos = RegExp(r'([\d.]+)\s+([\d.]+)\s+m').allMatches(stream);
      expect(
        moveTos,
        isNotEmpty,
        reason: 'expected at least one moveTo op in the content stream',
      );
      final minY = moveTos
          .map((m) => double.parse(m.group(2)!))
          .reduce((a, b) => a < b ? a : b);
      expect(
        minY,
        closeTo(10, 1),
        reason: 'stroke at canonical y=$canonicalHeight-10 should flip to '
            'PDF y≈10 (bottom of page); got min moveTo y=$minY. If this '
            'drifts, strokes land on the wrong side of the PDF page.',
      );
    });
  });
}

/// Finds the first FlateDecode stream in the raw PDF bytes and
/// inflates it. The `pdf` package writes page content (drawing ops)
/// into a FlateDecode-compressed stream; asserting on operator
/// positions requires inflating it.
String _decompressContentStream(Uint8List bytes) {
  const startTag = '/FlateDecode';
  const streamTag = 'stream\n';
  const endTag = '\nendstream';
  final asStr = String.fromCharCodes(bytes);
  var from = 0;
  while (true) {
    final flateAt = asStr.indexOf(startTag, from);
    if (flateAt < 0) return '';
    final streamAt = asStr.indexOf(streamTag, flateAt);
    if (streamAt < 0) return '';
    final payloadStart = streamAt + streamTag.length;
    final endAt = asStr.indexOf(endTag, payloadStart);
    if (endAt < 0) return '';
    final compressed = bytes.sublist(payloadStart, endAt);
    try {
      final inflated = ZLibCodec().decode(compressed);
      final text = String.fromCharCodes(inflated);
      // Content stream for the page will have a long sequence of `m` /
      // `l` / `S` ops. Skip resource dicts / short metadata that happen
      // to be Flate'd too.
      if (text.contains(' m ') && text.contains(' l ') && text.contains('S')) {
        return text;
      }
    } catch (_) {
      // Not a valid DEFLATE stream, skip.
    }
    from = endAt + endTag.length;
  }
}
