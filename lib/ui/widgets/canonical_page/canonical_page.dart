import 'package:flutter/material.dart';

import '../../screens/annotation_canvas/main_content.dart'
    show kAnnotatedContentWidth;

/// Hosts the spec markdown + ink stack at a canonical coordinate space
/// that is **the same every time**, independent of viewport width or
/// orientation. The viewport scales the canonical box down uniformly
/// when it's narrower than [kAnnotatedContentWidth]; when wider, the
/// canonical box renders at 1:1 centered horizontally and the extra
/// space shows the page background.
///
/// ## Why this exists
///
/// The previous `SizedBox(width: kAnnotatedContentWidth)` wrapper looked
/// like a lock but wasn't: `SizedBox` enforces its additional
/// constraints within the parent's constraints, so when an `Expanded`
/// gave it less than 960 logical px (portrait on the OnePlus Pad Go 2,
/// either screen — ~563 px on annotate, ~560 px on review), the
/// SizedBox collapsed to the parent's max and the `MarkdownBody` +
/// `InkOverlay` below reflowed / resized at that narrower width. Strokes
/// captured on a 960-wide layout and replayed on a 560-wide layout land
/// on different words.
///
/// ## How it locks
///
/// `OverflowBox(maxWidth=minWidth=kAnnotatedContentWidth)` forces the
/// child to exactly the canonical width regardless of parent
/// constraints. `Transform.scale(scale, alignment: topCenter)` shrinks
/// the canonical box visually to fit the viewport (never upscales —
/// `clamp(0, 1)`). `ClipRect` trims any 1-px anti-alias bleed past the
/// viewport edge.
///
/// ## Pointer-event invariant
///
/// `Transform` participates in hit-testing: Flutter inverts the scale
/// matrix when a pointer event descends into the subtree, so
/// `event.localPosition` at the `InkOverlay` Listener reports
/// **canonical (unscaled) coordinates** whether the user taps on
/// landscape (scale = 1) or portrait (scale < 1). Stored stroke paths
/// therefore live in one coordinate space — the canonical 960-wide
/// page — across every screen / orientation combo.
///
/// ## Vertical scroll
///
/// [SingleChildScrollView] wraps the child so long markdown can scroll.
/// The scroll extent is in canonical coords (the child's natural
/// intrinsic height); scroll deltas from gestures come in scaled-down
/// (canonical) units via the same transform-invert path, so a finger
/// dragging N physical pixels scrolls N physical pixels of content
/// regardless of `scale`.
class CanonicalPage extends StatelessWidget {
  const CanonicalPage({
    required this.child,
    this.scrollPhysics,
    super.key,
  });

  /// Expected to be a `Stack` whose first (non-positioned) child sets
  /// the page's natural height and whose `Positioned.fill` overlays
  /// paint the ink layer. See `main_content.dart` / `markdown_pane.dart`
  /// for the concrete shape — both must mirror each other exactly or
  /// the alignment bug re-appears.
  final Widget child;

  /// Forwarded to the inner [SingleChildScrollView]. `null` = default
  /// platform physics; `NeverScrollableScrollPhysics()` disables scroll
  /// (used by the annotation canvas while drawing so stylus samples
  /// don't steal the scroll gesture).
  final ScrollPhysics? scrollPhysics;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : kAnnotatedContentWidth;
        final maxH = constraints.hasBoundedHeight
            ? constraints.maxHeight
            : double.infinity;
        final scale = maxW <= 0
            ? 1.0
            : (maxW / kAnnotatedContentWidth).clamp(0.0, 1.0);
        // Canonical-space height of the scroll viewport. When scale < 1
        // the scroll viewport has more canonical vertical room than the
        // physical viewport; after Transform.scale it renders at exactly
        // [maxH].
        final canonicalViewportHeight =
            maxH.isFinite ? maxH / scale : double.infinity;
        return ClipRect(
          child: OverflowBox(
            alignment: Alignment.topCenter,
            minWidth: kAnnotatedContentWidth,
            maxWidth: kAnnotatedContentWidth,
            minHeight: canonicalViewportHeight,
            maxHeight: canonicalViewportHeight,
            child: Transform.scale(
              scale: scale,
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: kAnnotatedContentWidth,
                height: canonicalViewportHeight,
                child: SingleChildScrollView(
                  physics: scrollPhysics,
                  child: child,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
