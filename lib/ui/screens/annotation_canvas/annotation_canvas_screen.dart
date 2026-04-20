import 'package:flutter/material.dart';

import '../../theme/tokens.dart';
import 'left_rail.dart';
import 'main_content.dart';
import 'top_chrome.dart';

/// Screen 5 from the mockups — pen annotation overlay.
///
/// UI-spike scaffold (pre-T7). The body is composed of sibling widgets in
/// this folder (`top_chrome.dart`, `left_rail.dart`, `main_content.dart`)
/// so the file stays under the IMPLEMENTATION.md §2.6 200-line cap. T7
/// flips this to a `ConsumerStatefulWidget` wired to `AnnotationController`.
class AnnotationCanvasScreen extends StatelessWidget {
  const AnnotationCanvasScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      color: t.surfaceBackground,
      child: Column(
        children: [
          const AnnotationTopChrome(),
          Container(height: 1, color: t.borderSubtle),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const AnnotationLeftRail(),
                Container(width: 1, color: t.borderSubtle),
                const Expanded(child: AnnotationMainContent()),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
