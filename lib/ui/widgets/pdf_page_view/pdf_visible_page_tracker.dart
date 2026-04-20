import 'package:flutter/material.dart';

/// Computes the 1-indexed page whose centre is closest to the viewport
/// centre and reports changes via [onVisiblePageChanged].
///
/// Decoupled from [PdfPageView] so the "which page is in focus"
/// heuristic can evolve without churning the widget file. The tracker
/// makes one assumption: every page tile has the same height, supplied
/// via [pageHeight]. That's true under the MVP's fixed aspect-ratio
/// approximation; if T9's follow-up exposes per-page dimensions the
/// tracker grows a `List<double> pageHeights` instead.
class PdfVisiblePageTracker {
  PdfVisiblePageTracker({
    required this.scrollController,
    required this.onVisiblePageChanged,
    this.pageHeight = 1,
  });

  final ScrollController scrollController;
  final void Function(int page) onVisiblePageChanged;

  /// Tile height including vertical spacing. [PdfPageView] pushes the
  /// current value on every layout.
  double pageHeight;

  int _lastReported = -1;

  /// Recompute the current page; fire the callback only on change.
  /// Called from `ScrollController.addListener`.
  void update() {
    if (!scrollController.hasClients) return;
    if (pageHeight <= 0) return;
    final viewportHeight = scrollController.position.viewportDimension;
    final centre = scrollController.offset + (viewportHeight / 2);
    final pageIndex = (centre / pageHeight).floor();
    final page = pageIndex + 1;
    if (page == _lastReported) return;
    _lastReported = page;
    onVisiblePageChanged(page);
  }
}
