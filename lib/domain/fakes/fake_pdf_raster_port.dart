import 'dart:typed_data';

import '../entities/canvas_size.dart';
import '../entities/pdf_document_handle.dart';
import '../ports/pdf_raster_port.dart';

/// In-memory [PdfRasterPort] for domain + service tests. Zero I/O; every
/// call is scripted via [register] / [scriptOpenError] / [scriptRenderError]
/// and observable via [openedPaths] / [renderCalls] / [closedHandleIds].
///
/// The real `pdfx` adapter is exercised only by the integration test at
/// `integration_test/pdf_raster_test.dart` because it requires a Flutter
/// engine binding. See IMPLEMENTATION.md §4.4.
class FakePdfRasterPort implements PdfRasterPort {
  FakePdfRasterPort();

  /// 8-byte PNG signature (`\x89PNG\r\n\x1a\n`). Returned by [renderPage]
  /// when no per-page override is registered so callers' "is this a PNG?"
  /// checks succeed without a pixel payload. Kept as a local const rather
  /// than re-exported from `FakePngFlattener.defaultPngSignature` — the
  /// two fakes are in different bounded contexts (annotation rasterization
  /// vs. PDF rasterization) and sharing a constant would couple them.
  static final Uint8List defaultPngSignature = Uint8List.fromList(
    const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A],
  );

  final Map<String, _RegisteredDoc> _registered = {};
  final List<String> _openedPaths = [];
  final List<String> _closedHandleIds = [];
  final List<FakeRenderCall> _renderCalls = [];

  String? _pendingOpenError;
  String? _pendingRenderError;

  /// Register a document at [path] with [pageCount] pages and optional
  /// per-page PNG bytes. Unregistered paths throw [PdfOpenError].
  void register({
    required String path,
    required int pageCount,
    Map<int, Uint8List>? pagePngs,
  }) {
    _registered[path] = _RegisteredDoc(
      pageCount: pageCount,
      pagePngs: _copyPages(pagePngs),
    );
  }

  /// Arm the next [open] call to throw [PdfOpenError] with [message].
  /// Consumed after one throw, then normal behavior resumes.
  void scriptOpenError(String message) {
    _pendingOpenError = message;
  }

  /// Arm the next [renderPage] call to throw [PdfRenderError] with
  /// [message]. Consumed after one throw, then normal behavior resumes.
  void scriptRenderError(String message) {
    _pendingRenderError = message;
  }

  /// Every path passed to [open], in call order — including attempts that
  /// threw. Returned as an unmodifiable view.
  List<String> get openedPaths => List.unmodifiable(_openedPaths);

  /// Every handle id passed to [close], in call order. Returned as an
  /// unmodifiable view.
  List<String> get closedHandleIds => List.unmodifiable(_closedHandleIds);

  /// Every successful [renderPage] invocation, in call order. Throws do
  /// not record. Returned as an unmodifiable view.
  List<FakeRenderCall> get renderCalls => List.unmodifiable(_renderCalls);

  @override
  Future<PdfDocumentHandle> open(String filePath) async {
    _openedPaths.add(filePath);
    final scripted = _pendingOpenError;
    if (scripted != null) {
      _pendingOpenError = null;
      throw PdfOpenError(message: scripted, path: filePath);
    }
    final doc = _registered[filePath];
    if (doc == null) {
      throw PdfOpenError(message: 'not registered', path: filePath);
    }
    return PdfDocumentHandle(id: filePath, pageCount: doc.pageCount);
  }

  @override
  Future<Uint8List> renderPage({
    required PdfDocumentHandle handle,
    required int pageNumber,
    required CanvasSize targetSize,
  }) async {
    final doc = _registered[handle.id];
    if (doc == null || pageNumber < 1 || pageNumber > doc.pageCount) {
      throw RangeError.range(pageNumber, 1, doc?.pageCount ?? 0, 'pageNumber');
    }
    final scripted = _pendingRenderError;
    if (scripted != null) {
      _pendingRenderError = null;
      throw PdfRenderError(message: scripted, pageNumber: pageNumber);
    }
    _renderCalls.add(FakeRenderCall(
      handleId: handle.id,
      pageNumber: pageNumber,
      targetSize: targetSize,
    ));
    final override = doc.pagePngs[pageNumber];
    if (override != null) return Uint8List.fromList(override);
    return defaultPngSignature;
  }

  @override
  Future<void> close(PdfDocumentHandle handle) async {
    _closedHandleIds.add(handle.id);
  }

  static Map<int, Uint8List> _copyPages(Map<int, Uint8List>? src) {
    if (src == null) return const {};
    return {
      for (final e in src.entries) e.key: Uint8List.fromList(e.value),
    };
  }
}

/// One recorded invocation of [FakePdfRasterPort.renderPage].
class FakeRenderCall {
  const FakeRenderCall({
    required this.handleId,
    required this.pageNumber,
    required this.targetSize,
  });

  final String handleId;
  final int pageNumber;
  final CanvasSize targetSize;
}

class _RegisteredDoc {
  const _RegisteredDoc({required this.pageCount, required this.pagePngs});
  final int pageCount;
  final Map<int, Uint8List> pagePngs;
}
