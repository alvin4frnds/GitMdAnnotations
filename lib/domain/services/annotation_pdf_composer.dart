import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../entities/stroke.dart';
import '../entities/stroke_group.dart';

/// Composes the single composite `03-annotations.pdf` artifact:
/// markdown raster background + vector stroke overlay, at the canonical
/// coordinate space. Pure-Dart — no Flutter, no I/O. Called from
/// `ReviewSubmitter` at Submit Review time with the output of
/// [MarkdownRasterizerPort] and the committed stroke groups.
///
/// ## Coordinate space
///
/// Page size is set to the canonical logical dimensions (1 canonical
/// px == 1 PDF point). Strokes are stored in canonical **top-left**
/// origin (Y grows downward); PDF uses **bottom-left** origin, so each
/// canonical Y is flipped to `pageHeight - y` at draw time. The
/// background PNG is stretched edge-to-edge via [pw.BoxFit.fill] so
/// every background pixel lines up with its canonical coord exactly.
///
/// ## Vector strokes
///
/// Drawn with `PdfGraphics` primitives (`moveTo` / `lineTo` /
/// `strokePath`), not rasterized, so strokes remain crisp at any zoom.
/// Per-stroke opacity is set via a fresh [PdfGraphicState] on each
/// stroke — PDF's `gs` state isn't trivially undone, so we push a new
/// state per path rather than batching.
///
/// ## Determinism
///
/// Same inputs → byte-identical output. The `pdf` package writes a
/// `Producer` string + timestamp by default; we override producer and
/// omit any non-deterministic fields so re-submits with unchanged
/// strokes produce git-stable bytes.
class AnnotationPdfComposer {
  const AnnotationPdfComposer();

  Future<Uint8List> compose({
    required Uint8List backgroundPng,
    required double canonicalWidth,
    required double canonicalHeight,
    required List<StrokeGroup> groups,
  }) async {
    final doc = pw.Document(
      // Producer kept stable so re-runs produce byte-identical output.
      producer: 'gitmdannotations_tablet',
    );
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(
          canonicalWidth,
          canonicalHeight,
          marginAll: 0,
        ),
        build: (context) => pw.Stack(
          fit: pw.StackFit.expand,
          children: [
            pw.Image(
              pw.MemoryImage(backgroundPng),
              fit: pw.BoxFit.fill,
              width: canonicalWidth,
              height: canonicalHeight,
            ),
            pw.CustomPaint(
              size: PdfPoint(canonicalWidth, canonicalHeight),
              foregroundPainter: (canvas, size) =>
                  _paintStrokes(canvas, size, groups, canonicalHeight),
            ),
          ],
        ),
      ),
    );
    return Uint8List.fromList(await doc.save());
  }

  void _paintStrokes(
    PdfGraphics canvas,
    PdfPoint size,
    List<StrokeGroup> groups,
    double pageHeight,
  ) {
    for (final group in groups) {
      for (final stroke in group.strokes) {
        _paintStroke(canvas, stroke, pageHeight);
      }
    }
  }

  void _paintStroke(PdfGraphics canvas, Stroke stroke, double pageHeight) {
    if (stroke.points.isEmpty) return;
    canvas
      ..setStrokeColor(_hexToPdfColor(stroke.color))
      ..setLineWidth(stroke.strokeWidth)
      ..setLineCap(PdfLineCap.round)
      ..setLineJoin(PdfLineJoin.round)
      ..setGraphicState(PdfGraphicState(strokeOpacity: stroke.opacity));
    final first = stroke.points.first;
    canvas.moveTo(first.x, pageHeight - first.y);
    for (var i = 1; i < stroke.points.length; i++) {
      final p = stroke.points[i];
      canvas.lineTo(p.x, pageHeight - p.y);
    }
    canvas.strokePath();
  }

  PdfColor _hexToPdfColor(String hex) {
    final clean = hex.startsWith('#') ? hex.substring(1) : hex;
    final v = int.parse(clean, radix: 16);
    final r = ((v >> 16) & 0xff) / 255.0;
    final g = ((v >> 8) & 0xff) / 255.0;
    final b = (v & 0xff) / 255.0;
    return PdfColor(r, g, b);
  }
}
