import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/canvas_size.dart';
import '../../domain/entities/pdf_document_handle.dart';
import '../../domain/ports/pdf_raster_port.dart';
import '../../domain/services/pdf_page_cache.dart';

/// Binds the [PdfRasterPort] at the composition root. `bootstrap.dart`
/// wires `PdfxAdapter` in real mode and `FakePdfRasterPort` in mockup
/// mode; tests override with a scripted `FakePdfRasterPort` of their own.
/// Follows the T5 pattern from `annotation_providers.dart`.
final pdfRasterPortProvider = Provider<PdfRasterPort>((ref) {
  throw UnimplementedError(
    'pdfRasterPortProvider must be overridden at composition root',
  );
});

/// LRU cache wrapping the port. Single instance per scope — every screen
/// that opens a PDF shares the same page cache so a Repo-Picker-level
/// navigation doesn't multiply the memory budget (NFR-9). Default
/// capacity 8 matches `PdfPageCache`'s own default; override the
/// provider with a different `PdfPageCache(capacity: …)` if a composed
/// test needs a tighter budget.
final pdfPageCacheProvider = Provider<PdfPageCache>((ref) {
  return PdfPageCache(port: ref.watch(pdfRasterPortProvider));
});

/// Per-file PDF document notifier. `autoDispose` makes the handle close
/// when no widget watches it anymore (SpecReader pops); `family` keys on
/// the absolute file path so the same PDF watched from two routes
/// collapses to a single handle. `ref.onDispose` pairs every successful
/// `open` with a `close` — handles never leak past the widget lifetime.
///
/// IMPLEMENTATION.md §4.4 commits to lazy-loaded, bounded-memory PDF
/// rendering. This notifier is the "where the document lives" seam;
/// `pdfPageImageProvider` is the "where a page lives" seam.
final pdfDocumentNotifierProvider = AsyncNotifierProvider.autoDispose
    .family<PdfDocumentNotifier, PdfDocumentHandle, String>(
  PdfDocumentNotifier.new,
);

/// Owns the lifecycle of one open PDF document. `build` opens via the
/// cache; `ref.onDispose` schedules a close when the provider is torn
/// down. Errors thrown by `open` propagate as `AsyncValue.error` through
/// the normal `FutureProvider` machinery — widgets pattern-match with
/// `AsyncValue.when`.
class PdfDocumentNotifier
    extends AutoDisposeFamilyAsyncNotifier<PdfDocumentHandle, String> {
  @override
  Future<PdfDocumentHandle> build(String arg) async {
    final cache = ref.read(pdfPageCacheProvider);
    final handle = await cache.open(arg);
    // Close is intentionally fire-and-forget: `ref.onDispose` must be
    // sync per Riverpod's contract. The cache's `close` is idempotent
    // and errors are swallowed (bugs would surface through the port's
    // own logs; the widget is already gone).
    ref.onDispose(() {
      cache.close(handle);
    });
    return handle;
  }
}

/// Cache key for a single rasterized PDF page. [filePath] identifies
/// which document notifier to watch; [targetWidth]/[targetHeight] are
/// integers so that re-laying-out at an identical width reuses the same
/// key and hits the underlying [PdfPageCache]. Integer rounding avoids
/// the floating-point drift that would defeat value-equal keys.
class PdfPageImageKey {
  const PdfPageImageKey({
    required this.filePath,
    required this.pageNumber,
    required this.targetWidth,
    required this.targetHeight,
  });

  final String filePath;
  final int pageNumber;
  final int targetWidth;
  final int targetHeight;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PdfPageImageKey &&
          other.filePath == filePath &&
          other.pageNumber == pageNumber &&
          other.targetWidth == targetWidth &&
          other.targetHeight == targetHeight;

  @override
  int get hashCode =>
      Object.hash(filePath, pageNumber, targetWidth, targetHeight);
}

/// Per-page PNG bytes. `family` on a [PdfPageImageKey] so the widget
/// layer can `ref.watch` individual pages without rebuilding the whole
/// document. Cache coherence lives inside [PdfPageCache]; this provider
/// is the Riverpod-level caching seam so repeated `watch`es from the
/// same widget don't issue duplicate renders.
final pdfPageImageProvider = FutureProvider.autoDispose
    .family<Uint8List, PdfPageImageKey>((ref, key) async {
  final cache = ref.watch(pdfPageCacheProvider);
  // Wait for the document to be ready; throws if open failed.
  final handle = await ref.watch(
    pdfDocumentNotifierProvider(key.filePath).future,
  );
  return cache.renderPage(
    handle: handle,
    pageNumber: key.pageNumber,
    targetSize: CanvasSize(
      width: key.targetWidth.toDouble(),
      height: key.targetHeight.toDouble(),
    ),
  );
});
