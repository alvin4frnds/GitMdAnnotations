import 'dart:typed_data';

import '../entities/canvas_size.dart';
import '../entities/pdf_document_handle.dart';

/// Rasterizes a single page of a PDF to an image at a target logical size.
///
/// The domain signs a contract for "give me page N of this PDF rendered
/// approximately to size S." Device pixel ratio, format negotiation, and
/// any caching live inside the adapter (and the [PdfPageCache] wrapper).
///
/// IMPLEMENTATION.md §4.4 commits to `pdfx` as the fixed renderer (D-12),
/// but this port stays renderer-agnostic so the domain layer remains
/// Flutter- and library-free. §4.4's sketch returned `ui.Image`; we
/// override that here with a [Uint8List] PNG byte stream for the same
/// reason [PngFlattener] does — widgets convert via `Image.memory`
/// (§2.6 forbids `dart:ui` imports below the UI layer).
abstract class PdfRasterPort {
  /// Opens the PDF at [filePath] and returns a handle exposing
  /// [PdfDocumentHandle.pageCount]. The handle MUST be closed via [close]
  /// to release the underlying document. Throws [PdfOpenError] on any
  /// open failure (file not found, not a PDF, encrypted, corrupt).
  Future<PdfDocumentHandle> open(String filePath);

  /// Renders page [pageNumber] (1-indexed) of [handle] at the given
  /// [targetSize] in logical pixels. The returned bytes are a PNG-encoded
  /// image. Throws [PdfRenderError] on failure and [RangeError] when
  /// [pageNumber] is outside `1..handle.pageCount`.
  Future<Uint8List> renderPage({
    required PdfDocumentHandle handle,
    required int pageNumber,
    required CanvasSize targetSize,
  });

  /// Releases the underlying document. Idempotent — subsequent calls for
  /// the same handle are no-ops and MUST NOT throw.
  Future<void> close(PdfDocumentHandle handle);
}

/// Sealed root of every error a [PdfRasterPort] is allowed to throw
/// aside from [RangeError] (which indicates caller misuse of the
/// 1-indexed `pageNumber` contract). Callers pattern-match on concrete
/// subtypes; adapters translate raw platform exceptions into these so the
/// domain never sees them. See IMPLEMENTATION.md §2.6 (typed sealed
/// exceptions).
sealed class PdfError implements Exception {
  const PdfError();
}

/// Raised by [PdfRasterPort.open] when the PDF at [path] could not be
/// opened — file missing, not a PDF, encrypted, or corrupt. [message]
/// carries a human-readable cause supplied by the adapter.
class PdfOpenError extends PdfError {
  const PdfOpenError({required this.message, required this.path});

  final String message;
  final String path;

  @override
  String toString() => 'PdfOpenError(path: $path, message: $message)';
}

/// Raised by [PdfRasterPort.renderPage] when the adapter could not
/// rasterize [pageNumber]. [message] carries the underlying cause.
/// [RangeError] is used instead when [pageNumber] is out of bounds.
class PdfRenderError extends PdfError {
  const PdfRenderError({required this.message, required this.pageNumber});

  final String message;
  final int pageNumber;

  @override
  String toString() =>
      'PdfRenderError(pageNumber: $pageNumber, message: $message)';
}
