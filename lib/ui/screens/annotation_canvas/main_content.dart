import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../domain/entities/job_ref.dart';
import '../../../domain/entities/pointer_sample.dart';
import '../../../domain/entities/stroke.dart';
import '../../../domain/entities/stroke_group.dart';
import '../../theme/tokens.dart';
import '../../widgets/ink_overlay/ink_overlay.dart';
import 'markdown_stub.dart';

/// Shared content width for both the annotation canvas and the review
/// panel's left pane. Locking the markdown to a canonical logical width
/// makes line-wraps identical in both screens so strokes captured in
/// content-local coordinates on one screen land on the same underlying
/// text on the other (the review panel's left pane is narrower than the
/// canvas main area because the 420-px typed-review panel eats the right
/// side). Exported so `review_panel/markdown_pane.dart` uses the exact
/// same number.
const double kAnnotatedContentWidth = 900;

/// Padding wrapped around the markdown inside the ink stack. Exported so
/// the review pane can mirror it exactly — if the two screens drift on
/// this number, strokes stored on one re-render at a different offset
/// on the other.
const EdgeInsets kAnnotatedContentPadding =
    EdgeInsets.fromLTRB(48, 32, 48, 32);

/// Main content for the annotation canvas — real spec markdown behind a
/// live `InkOverlay`, both constrained to [kAnnotatedContentWidth] and
/// centered so the content has the same layout geometry across screens.
///
/// The ink overlay sits **inside** the scroll view, layered over the
/// markdown via a `Stack`. Pointer samples are therefore captured in
/// *content-local* coordinates — scrolling the view shifts both the
/// markdown and the already-committed strokes in lock-step, and the
/// review pane can paint the same strokes at the same content-local
/// positions to keep alignment with the underlying text.
///
/// `hitTestBehavior: HitTestBehavior.opaque` paired with an
/// `IgnorePointer(ignoring: !drawingEnabled)` wrapper lets the overlay
/// eat pointer events while in pen/highlighter mode and pass them
/// through to the scroll view in view (Pan) mode.
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
      alignment: Alignment.topCenter,
      child: SizedBox(
        width: kAnnotatedContentWidth,
        child: SingleChildScrollView(
          physics: drawingEnabled
              ? const NeverScrollableScrollPhysics()
              : const BouncingScrollPhysics(),
          child: Stack(
            children: [
              // Forcing `width: double.infinity` is deliberate — without
              // it the Stack's non-positioned child gets loose
              // constraints and `MarkdownBody(shrinkWrap: true)` sizes
              // down to its intrinsic *text* width. The Stack would
              // then shrink to that text box and the `Positioned.fill`
              // InkOverlay would shrink with it, making the left/right
              // page margins unreachable to the stylus — user could
              // only start a stroke on a line that already had text
              // under it.
              SizedBox(
                width: double.infinity,
                child: Padding(
                  padding: kAnnotatedContentPadding,
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
        ),
      ),
    );
  }
}
