import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../domain/entities/job_ref.dart';
import '../../../domain/entities/pointer_sample.dart';
import '../../../domain/entities/stroke.dart';
import '../../../domain/entities/stroke_group.dart';
import '../../theme/tokens.dart';
import '../../widgets/canonical_page/canonical_page.dart';
import '../../widgets/ink_overlay/ink_overlay.dart';
import 'markdown_stub.dart';

/// Canonical logical width of the annotated page. Strokes are captured
/// and replayed in a coordinate space this wide, on **every** screen
/// (annotate / review) and **every** orientation. [CanonicalPage]
/// always zoom-scales this canonical box to exactly fill the viewport
/// width — scales *down* in portrait, scales *up* in landscape. The
/// canonical width is the only width at which the markdown is ever
/// laid out, so line wraps are identical in every combo and stored
/// stroke coordinates always point at the same underlying text.
///
/// Picked 900 rather than matching the narrowest viewport: gives enough
/// room for spec formatting (headings, code blocks) without bumping
/// into the review-pane-side landscape cap, and the zoom-to-fill
/// rendering means we get the same coordinate space regardless.
///
/// Changing this number changes the coordinate space: existing
/// `03-annotations.svg` files captured at the old width would replay at
/// a visually scaled offset. Treat it as a repo-wide invariant — if it
/// must change, plan a rewrite pass over existing annotation artifacts.
///
/// Exported so `review_panel/markdown_pane.dart` uses the exact same
/// number.
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
/// Pointer routing in this subtree:
///   * Stylus samples reach the `InkOverlay.Listener` (opaque) and the
///     [_AnnotationScrollBehavior] excludes stylus from `dragDevices` in
///     pen mode, so stylus drags never initiate a scroll — they draw.
///   * Touch samples are dropped by the overlay (via
///     `allowedPointerKindsProvider`) but still reach the scroll view's
///     `VerticalDragGestureRecognizer` via the gesture arena, so finger
///     swipes scroll the content while pen mode is active.
///   * While a stylus stroke is actively in flight, physics flips to
///     `NeverScrollableScrollPhysics` as palm rejection — a resting
///     palm that registers as touch must not drift the page mid-stroke.
///
/// `IgnorePointer(ignoring: !drawingEnabled)` still gates the overlay
/// in pan mode so all pointers fall through to the scroll view.
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
    this.hasActiveStylusStroke = false,
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

  /// `true` while a stylus stroke is mid-flight. Freezes scroll physics
  /// so a resting palm can't scroll the page out from under the stroke.
  final bool hasActiveStylusStroke;
  final void Function(InkPointerPhase phase, PointerSample sample) onSample;
  final DateTime Function() nowProvider;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      color: t.surfaceElevated,
      alignment: Alignment.topCenter,
      child: ScrollConfiguration(
        behavior: _AnnotationScrollBehavior(
          allowStylusScroll: !drawingEnabled,
        ),
        child: CanonicalPage(
          scrollPhysics: hasActiveStylusStroke
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

/// Restricts which pointer kinds can initiate a scroll drag in the
/// annotation canvas. In pen/highlighter mode (`allowStylusScroll:
/// false`) stylus is excluded so stylus drags reach only the opaque
/// `Listener` in `InkOverlay` and draw cleanly — while touch, mouse,
/// and trackpad still scroll. In pan mode (`allowStylusScroll: true`)
/// stylus scrolls too, matching the pre-change behavior of Pan mode.
class _AnnotationScrollBehavior extends MaterialScrollBehavior {
  const _AnnotationScrollBehavior({required this.allowStylusScroll});

  final bool allowStylusScroll;

  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.invertedStylus,
        if (allowStylusScroll) PointerDeviceKind.stylus,
      };
}
