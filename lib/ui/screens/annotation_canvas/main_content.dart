import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../domain/entities/job_ref.dart';
import '../../../domain/entities/pointer_sample.dart';
import '../../../domain/entities/stroke.dart';
import '../../../domain/entities/stroke_group.dart';
import '../../theme/tokens.dart';
import '../../widgets/ink_overlay/ink_overlay.dart';
import 'markdown_stub.dart';

/// Main content for the annotation canvas — real spec markdown behind a
/// live `InkOverlay`. The overlay is `HitTestBehavior.opaque` while
/// drawing is enabled (edit/highlight tools) so stylus samples hit the
/// overlay first; in "view" mode the overlay lets gestures fall through
/// so the content behind can be scrolled.
class AnnotationMainContent extends StatelessWidget {
  const AnnotationMainContent({
    required this.jobRef,
    required this.groups,
    required this.activeStroke,
    required this.currentStrokeColor,
    required this.currentStrokeWidth,
    required this.onSample,
    required this.nowProvider,
    this.drawingEnabled = true,
    this.currentStrokeOpacity = Stroke.kDefaultStrokeOpacity,
    super.key,
  });

  final JobRef jobRef;
  final List<StrokeGroup> groups;
  final ValueListenable<List<Offset>> activeStroke;
  final Color currentStrokeColor;
  final double currentStrokeWidth;
  final double currentStrokeOpacity;
  final bool drawingEnabled;
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
          Padding(
            padding: const EdgeInsets.fromLTRB(48, 32, 48, 32),
            child: SingleChildScrollView(
              physics: drawingEnabled
                  ? const NeverScrollableScrollPhysics()
                  : const BouncingScrollPhysics(),
              child: MarkdownStub(jobRef: jobRef),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              ignoring: !drawingEnabled,
              child: InkOverlay(
                groups: groups,
                activeStroke: activeStroke,
                currentStrokeColor: currentStrokeColor,
                currentStrokeWidth: currentStrokeWidth,
                currentStrokeOpacity: currentStrokeOpacity,
                onSample: onSample,
                nowProvider: nowProvider,
                hitTestBehavior: HitTestBehavior.opaque,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
