/// Opaque, pure-Dart handle to an opened PDF document returned from
/// [PdfRasterPort.open]. Carries just an [id] (assigned by the adapter) and
/// [pageCount] so domain code can iterate pages without knowing anything
/// about the underlying renderer.
///
/// Equality is keyed on [id] alone so that two lookups of the same document
/// compare equal even if a caller re-reads [pageCount] through a different
/// code path. IMPLEMENTATION.md §4.4 keeps this type Flutter- and
/// renderer-free; the real `pdfx` document reference is looked up inside
/// the adapter via this id, not exposed to the domain.
class PdfDocumentHandle {
  PdfDocumentHandle({required this.id, required this.pageCount}) {
    if (id.isEmpty) {
      throw ArgumentError.value(id, 'id', 'must be non-empty');
    }
    if (pageCount < 0) {
      throw ArgumentError.value(pageCount, 'pageCount', 'must be >= 0');
    }
  }

  /// Adapter-chosen opaque identifier. The [FakePdfRasterPort] uses the
  /// registered file path; the real `pdfx` adapter mints a session-unique
  /// id so two opens of the same file produce independent handles.
  final String id;

  /// Number of pages in the document. `renderPage` must receive a
  /// `pageNumber` in `1..pageCount`.
  final int pageCount;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PdfDocumentHandle && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'PdfDocumentHandle(id: $id, pageCount: $pageCount)';
}
