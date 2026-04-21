import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers/annotation_providers.dart';
import '../../../domain/entities/job_ref.dart';
import '../../../domain/entities/stroke_group.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/canonical_page/canonical_page.dart';
import '../../widgets/ink_overlay/ink_painting.dart';
import '../annotation_canvas/main_content.dart'
    show kAnnotatedContentPadding, kAnnotatedContentWidth;
import '../annotation_canvas/markdown_stub.dart';

/// Left pane of the review screen — real spec markdown plus the
/// read-only stroke overlay that replays whatever the user drew on the
/// AnnotationCanvas.
///
/// Shares the canonical [kAnnotatedContentWidth] coordinate space with
/// the annotation canvas via [CanonicalPage], which is how strokes
/// stored in canonical content-local coords on the canvas re-paint at
/// the same canonical coords here regardless of this pane's actual
/// viewport width (portrait vs landscape, narrow-pane splits, etc.).
class MarkdownPane extends ConsumerWidget {
  const MarkdownPane({required this.jobRef, super.key});

  final JobRef jobRef;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final strokeGroups = ref.watch(annotationControllerProvider(jobRef)).groups;
    return Container(
      color: t.surfaceElevated,
      alignment: Alignment.topCenter,
      child: CanonicalPage(
        child: Stack(
          children: [
            // `width: double.infinity` mirrors the canvas side
            // (`annotation_canvas/main_content.dart`). Without it the
            // Stack's non-positioned child shrinks to the markdown
            // text width and the stroke painter would clip strokes
            // drawn in the left/right margins.
            //
            // Markdown forced to light tokens, matching the annotate
            // canvas side. Keeps the review-panel markdown readable in
            // dark mode AND keeps line-wrap identical to the rasterized
            // PDF background, so the read-only stroke overlay lines up
            // with the same underlying text the user drew over.
            Theme(
              data: AppTheme.build(AppTokens.light),
              child: ColoredBox(
                color: AppTokens.light.surfaceElevated,
                child: SizedBox(
                  width: double.infinity,
                  child: Padding(
                    padding: kAnnotatedContentPadding,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        MarkdownStub(jobRef: jobRef),
                        const SizedBox(height: 24),
                        Builder(
                          builder: (ctx) => Text(
                            _annotationSummary(strokeGroups),
                            style: TextStyle(
                              color: ctx.tokens.textMuted,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (strokeGroups.isNotEmpty)
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _ReadOnlyStrokesPainter(groups: strokeGroups),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _annotationSummary(List<StrokeGroup> groups) {
    if (groups.isEmpty) return 'No annotations yet';
    final strokes = groups.fold<int>(0, (sum, g) => sum + g.strokes.length);
    final groupLabel = groups.length == 1 ? 'stroke group' : 'stroke groups';
    final strokeLabel = strokes == 1 ? 'stroke' : 'strokes';
    return '${groups.length} $groupLabel . $strokes $strokeLabel';
  }
}

/// Read-only painter that replays the committed stroke groups on top of
/// the review-panel left pane so the user sees what they drew on the
/// annotation canvas. Paints in the same content-local coordinate space
/// the canvas used (see [kAnnotatedContentWidth] +
/// [kAnnotatedContentPadding]).
class _ReadOnlyStrokesPainter extends CustomPainter {
  const _ReadOnlyStrokesPainter({required this.groups});

  final List<StrokeGroup> groups;

  @override
  void paint(Canvas canvas, Size size) {
    paintStrokeGroups(
      canvas,
      groups: groups,
      activeStrokePoints: const <Offset>[],
      activeStrokeColor: const Color(0x00000000),
      activeStrokeWidth: 0,
    );
  }

  @override
  bool shouldRepaint(covariant _ReadOnlyStrokesPainter old) =>
      !identical(old.groups, groups);
}
