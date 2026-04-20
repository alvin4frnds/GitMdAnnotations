import 'dart:typed_data';

import 'package:pdfx/pdfx.dart' as pdfx;

import '../../domain/entities/canvas_size.dart';
import '../../domain/entities/pdf_document_handle.dart';
import '../../domain/ports/pdf_raster_port.dart';

/// Production [PdfRasterPort] adapter backed by the `pdfx` package
/// (IMPLEMENTATION.md §4.4 / D-12 — MIT-licensed, open source, fixed
/// renderer for Phase 1). The adapter is the only place in the codebase
/// allowed to import `package:pdfx/*`; everything above the `infra/pdf`
/// boundary speaks the pure-Dart [PdfRasterPort] surface.
///
/// Handle-id strategy: a self-contained micros+counter generator inside
/// this file. `SystemIdGenerator` (T5) would work too, but its ids carry a
/// `stroke-group-` prefix that belongs to the annotation bounded context;
/// minting `stroke-group-…` ids for PDF documents would leak vocabulary
/// across domains and the lint rule in §2.6 about ubiquitous language
/// would flag it on review. A 16-line private generator keeps the scheme
/// local without creating a public `IdGenerator` port subclass for every
/// infra bounded context.
class PdfxAdapter implements PdfRasterPort {
  PdfxAdapter() : _idGen = _PdfHandleIdGenerator();

  final _PdfHandleIdGenerator _idGen;
  final Map<String, pdfx.PdfDocument> _docs = {};

  @override
  Future<PdfDocumentHandle> open(String filePath) async {
    final pdfx.PdfDocument doc;
    try {
      doc = await pdfx.PdfDocument.openFile(filePath);
    } on Object catch (e) {
      throw PdfOpenError(message: e.toString(), path: filePath);
    }
    final id = _idGen.next();
    _docs[id] = doc;
    return PdfDocumentHandle(id: id, pageCount: doc.pagesCount);
  }

  @override
  Future<Uint8List> renderPage({
    required PdfDocumentHandle handle,
    required int pageNumber,
    required CanvasSize targetSize,
  }) async {
    final doc = _docs[handle.id];
    if (doc == null || pageNumber < 1 || pageNumber > doc.pagesCount) {
      throw RangeError.range(
        pageNumber,
        1,
        doc?.pagesCount ?? 0,
        'pageNumber',
      );
    }
    pdfx.PdfPage? page;
    try {
      page = await doc.getPage(pageNumber);
      final image = await page.render(
        width: targetSize.width.round().toDouble(),
        height: targetSize.height.round().toDouble(),
        format: pdfx.PdfPageImageFormat.png,
      );
      if (image == null) {
        throw PdfRenderError(
          message: 'pdfx returned null image',
          pageNumber: pageNumber,
        );
      }
      return image.bytes;
    } on PdfRenderError {
      rethrow;
    } on Object catch (e) {
      throw PdfRenderError(message: e.toString(), pageNumber: pageNumber);
    } finally {
      await page?.close();
    }
  }

  @override
  Future<void> close(PdfDocumentHandle handle) async {
    final doc = _docs.remove(handle.id);
    if (doc == null) return; // idempotent: already closed or never opened.
    await doc.close();
  }
}

/// Session-scoped id generator for PDF document handles. The scheme is
/// cosmetic (§4.4 only requires opaque + per-session unique); we pick
/// `pdf-doc-<micros36>-<counter>` for grep-ability in logs. Not a
/// public port — PDF handles live entirely inside this adapter.
class _PdfHandleIdGenerator {
  _PdfHandleIdGenerator()
      : _seed = DateTime.now().microsecondsSinceEpoch.toRadixString(36);

  final String _seed;
  int _counter = 0;

  String next() {
    final id = 'pdf-doc-$_seed-$_counter';
    _counter++;
    return id;
  }
}
