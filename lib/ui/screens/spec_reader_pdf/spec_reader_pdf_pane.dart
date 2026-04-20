import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../domain/entities/pdf_document_handle.dart';
import '../../../domain/entities/pointer_sample.dart';
import '../../../domain/entities/stroke_group.dart';
import '../../theme/tokens.dart';
import '../../widgets/ink_overlay/ink_overlay.dart';
import '../../widgets/pdf_page_view/pdf_page_view.dart';

/// Main content pane: PDF page view behind a live [InkOverlay].
///
/// Stack order: [PdfPageView] at the bottom, [InkOverlay] on top with
/// `HitTestBehavior.opaque`. The overlay's `Listener` swallows touch
/// events the underlying `InteractiveViewer` would otherwise use for
/// pan/zoom — acceptable tradeoff for T9 (stylus-only). A toolbar-
/// driven pen/pan toggle is queued for a follow-up (Issues.md).
class SpecReaderPdfPane extends StatelessWidget {
  const SpecReaderPdfPane({
    required this.filePath,
    required this.handle,
    required this.groups,
    required this.activeStroke,
    required this.onSample,
    required this.nowProvider,
    required this.onVisiblePageChanged,
    super.key,
  });

  final String filePath;
  final PdfDocumentHandle handle;
  final List<StrokeGroup> groups;
  final ValueListenable<List<Offset>> activeStroke;
  final void Function(InkPointerPhase phase, PointerSample sample) onSample;
  final DateTime Function() nowProvider;
  final void Function(int page) onVisiblePageChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      color: t.surfaceElevated,
      child: Stack(
        fit: StackFit.expand,
        children: [
          PdfPageView(
            filePath: filePath,
            handle: handle,
            onVisiblePageChanged: onVisiblePageChanged,
          ),
          Positioned.fill(
            child: InkOverlay(
              groups: groups,
              activeStroke: activeStroke,
              currentStrokeColor: t.inkRed,
              currentStrokeWidth: 2,
              onSample: onSample,
              nowProvider: nowProvider,
              hitTestBehavior: HitTestBehavior.opaque,
            ),
          ),
        ],
      ),
    );
  }
}
