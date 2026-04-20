import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers/pdf_providers.dart';

/// Renders one PDF page from [pdfPageImageProvider] as an
/// [Image.memory], showing a small progress indicator while bytes are
/// being rasterized and a page-level error box if the port threw.
///
/// Exposed (not file-private) so tests can assert on
/// `find.byType(PdfPageTile)` without reaching into [PdfPageView]'s
/// internals — matches T7's pattern of exposing the tile types that
/// make widget tests greppable.
class PdfPageTile extends ConsumerWidget {
  const PdfPageTile({
    required this.filePath,
    required this.pageNumber,
    required this.targetWidth,
    required this.targetHeight,
    this.onTapUp,
    super.key,
  });

  final String filePath;
  final int pageNumber;
  final int targetWidth;
  final int targetHeight;
  final void Function(Offset localOffset)? onTapUp;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = PdfPageImageKey(
      filePath: filePath,
      pageNumber: pageNumber,
      targetWidth: targetWidth,
      targetHeight: targetHeight,
    );
    final async = ref.watch(pdfPageImageProvider(key));
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: (details) => onTapUp?.call(details.localPosition),
      child: async.when(
        data: (bytes) => Image.memory(
          bytes,
          fit: BoxFit.contain,
          gaplessPlayback: true,
          filterQuality: FilterQuality.medium,
          errorBuilder: (_, e, s) => _ErrorBox(pageNumber: pageNumber),
        ),
        loading: () => const Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
        error: (_, s) => _ErrorBox(pageNumber: pageNumber),
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.pageNumber});

  final int pageNumber;

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.08),
        border: Border.all(color: Colors.red.withValues(alpha: 0.4)),
      ),
      child: Text(
        'Failed to render page $pageNumber',
        style: const TextStyle(fontSize: 13, color: Colors.red),
      ),
    );
  }
}
