import 'dart:collection';
import 'dart:typed_data';

import '../entities/canvas_size.dart';
import '../entities/pdf_document_handle.dart';
import '../ports/pdf_raster_port.dart';

/// LRU cache wrapper around a [PdfRasterPort]. Keeps at most [capacity]
/// rendered pages across all open documents; on hit returns cached bytes
/// without re-calling the port, on overflow evicts the oldest entry.
///
/// IMPLEMENTATION.md §4.4 calls for lazy-loaded, bounded-memory PDF
/// rendering so a 200-page spec can be browsed without keeping all pages
/// resident. The cache is scoped per-[PdfPageCache] instance, not global,
/// so the composition root can hand different PDFs their own budgets.
///
/// Cache key: `(handleId, pageNumber, CanvasSize)`. `CanvasSize` carries
/// `==`/`hashCode` (T4) so the tuple collapses cleanly into a Dart `Map`
/// key via a small record. Closing a handle drops every entry keyed on
/// that handle's id — memory hygiene over stale bytes.
class PdfPageCache {
  PdfPageCache({required PdfRasterPort port, int capacity = 8})
      : _port = port,
        _capacity = capacity {
    if (capacity <= 0) {
      throw ArgumentError.value(capacity, 'capacity', 'must be > 0');
    }
  }

  final PdfRasterPort _port;
  final int _capacity;

  /// Ordered by insertion/promotion; oldest entry is `first`.
  final LinkedHashMap<_CacheKey, Uint8List> _entries =
      LinkedHashMap<_CacheKey, Uint8List>();

  /// Ids we've already forwarded to `_port.close`. Guards against
  /// double-close cascades — the provider layer fires `ref.onDispose`
  /// blindly and a real `pdfx` document cannot be closed twice without
  /// crashing.
  final Set<String> _closedHandleIds = <String>{};

  /// Current number of cached pages.
  int get size => _entries.length;

  /// Maximum number of cached pages the cache will hold before evicting.
  int get capacity => _capacity;

  /// Passes through to the underlying port. Clears the "already closed"
  /// mark for this id so a subsequent [close] on the freshly-opened
  /// handle forwards to the port — re-opening is not idempotency.
  Future<PdfDocumentHandle> open(String filePath) async {
    final handle = await _port.open(filePath);
    _closedHandleIds.remove(handle.id);
    return handle;
  }

  /// Renders page [pageNumber] at [targetSize], serving from cache on hit
  /// and otherwise delegating to the port + memoizing the result.
  Future<Uint8List> renderPage({
    required PdfDocumentHandle handle,
    required int pageNumber,
    required CanvasSize targetSize,
  }) async {
    final key = _CacheKey(handle.id, pageNumber, targetSize);
    final cached = _entries.remove(key);
    if (cached != null) {
      _entries[key] = cached; // promote to most-recent.
      return cached;
    }
    final bytes = await _port.renderPage(
      handle: handle,
      pageNumber: pageNumber,
      targetSize: targetSize,
    );
    _entries[key] = bytes;
    if (_entries.length > _capacity) {
      _entries.remove(_entries.keys.first);
    }
    return bytes;
  }

  /// Closes the handle on the underlying port and evicts every cache
  /// entry keyed on [handle]'s id. Idempotent: a second call with the
  /// same handle is a silent no-op — the provider layer can fire
  /// `ref.onDispose` without tracking whether close already ran.
  Future<void> close(PdfDocumentHandle handle) async {
    if (!_closedHandleIds.add(handle.id)) {
      return;
    }
    _entries.removeWhere((key, _) => key.handleId == handle.id);
    await _port.close(handle);
  }
}

/// Internal cache key. Dart records would work too, but a class with
/// explicit `==`/`hashCode` is easier to grep for and keeps the
/// `LinkedHashMap` contract explicit.
class _CacheKey {
  const _CacheKey(this.handleId, this.pageNumber, this.targetSize);

  final String handleId;
  final int pageNumber;
  final CanvasSize targetSize;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _CacheKey &&
          other.handleId == handleId &&
          other.pageNumber == pageNumber &&
          other.targetSize == targetSize;

  @override
  int get hashCode => Object.hash(handleId, pageNumber, targetSize);
}
