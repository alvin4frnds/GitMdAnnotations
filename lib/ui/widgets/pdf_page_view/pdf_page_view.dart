import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/entities/pdf_document_handle.dart';
import 'pdf_page_tile.dart';
import 'pdf_visible_page_tracker.dart';

/// Scrollable, lazy-loading view of a PDF's pages wrapped in an
/// [InteractiveViewer] for pinch-zoom.
///
/// IMPLEMENTATION.md §4.4 specifies lazy page loads, fit-to-width
/// default, pinch-zoom, and no native text selection. This widget owns
/// the list + zoom; per-page rasterization is delegated to
/// [PdfPageTile] which watches `pdfPageImageProvider`.
///
/// The widget is kept deliberately presentation-only: no writes to
/// `annotationControllerProvider`, no anchor derivation. `onPageTap`
/// and `onVisiblePageChanged` are the only call-outs, so the parent
/// screen can wire anchor resolution and scrollspy chrome without
/// coupling the widget to the annotation bounded context.
class PdfPageView extends ConsumerStatefulWidget {
  const PdfPageView({
    required this.filePath,
    required this.handle,
    this.onPageTap,
    this.onVisiblePageChanged,
    this.pageSpacing = 12,
    this.pageAspectRatio = _defaultAspectRatio,
    super.key,
  });

  final String filePath;
  final PdfDocumentHandle handle;

  /// Called on tap-up inside a page tile. [localOffsetInPage] is measured
  /// from the tile's top-left in logical pixels; the caller converts to
  /// PDF-page coordinates when deriving a [PdfAnchor].
  final void Function(int page, Offset localOffsetInPage)? onPageTap;

  /// Emitted when the page whose centre is closest to the viewport
  /// centre changes. Useful for scrollspy-style page counters or
  /// outline-rail highlighting.
  final void Function(int page)? onVisiblePageChanged;

  /// Vertical gap between pages. 12 logical px matches the mockup
  /// spacing.
  final double pageSpacing;

  /// Page height / page width. Real aspect ratios are page-specific and
  /// not exposed by [PdfRasterPort] today — see Issues.md. 1.4 ≈ A4
  /// portrait is a sensible default for most specs and docs.
  final double pageAspectRatio;

  /// `1 / sqrt(2) ≈ 0.707` inverted to 1.4142 — A4 portrait aspect.
  /// Hard-coded constant keeps the widget free of a `dart:math` import.
  static const double _defaultAspectRatio = 1.4142;

  @override
  ConsumerState<PdfPageView> createState() => _PdfPageViewState();
}

class _PdfPageViewState extends ConsumerState<PdfPageView> {
  final _scrollController = ScrollController();
  late final PdfVisiblePageTracker _tracker;

  @override
  void initState() {
    super.initState();
    _tracker = PdfVisiblePageTracker(
      scrollController: _scrollController,
      onVisiblePageChanged: (page) =>
          widget.onVisiblePageChanged?.call(page),
    );
    _scrollController.addListener(_tracker.update);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_tracker.update);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final pageWidth = constraints.maxWidth;
        final pageHeight = pageWidth * widget.pageAspectRatio;
        final dpr = MediaQuery.devicePixelRatioOf(context);
        // Nudge the tracker with the current tile height so visibility
        // math doesn't have to re-measure.
        _tracker.pageHeight = pageHeight + widget.pageSpacing;
        return InteractiveViewer(
          minScale: 0.5,
          maxScale: 6,
          boundaryMargin: const EdgeInsets.all(100),
          child: ListView.builder(
            controller: _scrollController,
            itemCount: widget.handle.pageCount,
            itemBuilder: (context, index) {
              final pageNumber = index + 1;
              return Padding(
                padding: EdgeInsets.only(
                  bottom: widget.pageSpacing,
                  top: index == 0 ? widget.pageSpacing : 0,
                ),
                child: SizedBox(
                  width: pageWidth,
                  height: pageHeight,
                  child: PdfPageTile(
                    filePath: widget.filePath,
                    pageNumber: pageNumber,
                    targetWidth: (pageWidth * dpr).round(),
                    targetHeight: (pageHeight * dpr).round(),
                    onTapUp: (local) =>
                        widget.onPageTap?.call(pageNumber, local),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
