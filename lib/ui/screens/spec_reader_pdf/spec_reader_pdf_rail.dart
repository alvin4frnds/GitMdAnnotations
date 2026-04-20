import 'package:flutter/material.dart';

import '../../theme/tokens.dart';

/// Left rail for the PDF spec reader. The markdown variant shows an
/// H2/H3 outline; a PDF has no semantic headings without OCR, so the
/// rail lists page numbers — mirrors the "page N of M" chrome most PDF
/// viewers surface. The active item tracks [currentPage] so the viewer
/// can scrollspy-highlight as the user pages through.
class SpecReaderPdfRail extends StatelessWidget {
  const SpecReaderPdfRail({
    required this.pageCount,
    required this.currentPage,
    super.key,
  });

  final int pageCount;
  final int currentPage;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      width: 200,
      color: t.surfaceElevated,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _RailHeader(label: 'Pages'),
          const SizedBox(height: 8),
          for (var i = 1; i <= pageCount; i++)
            _PageItem(page: i, active: i == currentPage),
        ],
      ),
    );
  }
}

class _RailHeader extends StatelessWidget {
  const _RailHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Text(
      label.toUpperCase(),
      style: TextStyle(
        color: t.textMuted,
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
      ),
    );
  }
}

class _PageItem extends StatelessWidget {
  const _PageItem({required this.page, required this.active});
  final int page;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Text(
        'Page $page',
        style: TextStyle(
          color: active ? t.accentPrimary : t.textPrimary,
          fontSize: 12,
          fontWeight: active ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
    );
  }
}
