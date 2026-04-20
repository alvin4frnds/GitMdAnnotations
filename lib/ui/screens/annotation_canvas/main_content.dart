import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../domain/entities/pointer_sample.dart';
import '../../../domain/entities/stroke_group.dart';
import '../../theme/tokens.dart';
import '../../widgets/ink_overlay/ink_overlay.dart';
import 'markdown_stub.dart';

/// Main content for the annotation canvas — markdown stub behind a live
/// `InkOverlay`. T7 replaces the pre-wire legacy mockup painter + hardcoded
/// margin notes (they lived here as display chrome only) with committed
/// state from [annotationControllerProvider].
class AnnotationMainContent extends StatelessWidget {
  const AnnotationMainContent({
    required this.groups,
    required this.activeStroke,
    required this.currentStrokeColor,
    required this.currentStrokeWidth,
    required this.onSample,
    required this.nowProvider,
    super.key,
  });

  final List<StrokeGroup> groups;
  final ValueListenable<List<Offset>> activeStroke;
  final Color currentStrokeColor;
  final double currentStrokeWidth;
  final void Function(InkPointerPhase phase, PointerSample sample) onSample;
  final DateTime Function() nowProvider;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      color: t.surfaceElevated,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Rendered markdown stub — real `MarkdownRenderer` (§4.4) is a
          // later task; keeping the stub preserves the mockup's visual
          // fidelity when browsed in the mockup shell.
          const Padding(
            padding: EdgeInsets.fromLTRB(48, 32, 48, 32),
            child: SingleChildScrollView(
              physics: NeverScrollableScrollPhysics(),
              child: MarkdownStub(),
            ),
          ),
          Positioned.fill(
            child: InkOverlay(
              groups: groups,
              activeStroke: activeStroke,
              currentStrokeColor: currentStrokeColor,
              currentStrokeWidth: currentStrokeWidth,
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
