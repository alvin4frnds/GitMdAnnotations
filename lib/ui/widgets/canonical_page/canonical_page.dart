import 'package:flutter/material.dart';

import '../../screens/annotation_canvas/main_content.dart'
    show kAnnotatedContentWidth;

/// Hosts the spec markdown + ink stack at a canonical coordinate space
/// that is **the same every time**, independent of viewport width or
/// orientation. The canonical box is always laid out at
/// [kAnnotatedContentWidth] logical pixels; the visual rendering is
/// uniformly **zoom-to-filled** to the viewport width — scaled down in
/// portrait, scaled up in landscape. Stored stroke coordinates are
/// always in canonical space, so a stroke drawn in one orientation
/// replays on the same underlying text in any other orientation.
///
/// ## Why this exists
///
/// A `SizedBox(width: kAnnotatedContentWidth)` wrapper looks like a
/// lock but isn't: `SizedBox` enforces its additional constraints only
/// *within* the parent's constraints. When the parent gives less width
/// than the canonical value (portrait on the OnePlus Pad Go 2 on
/// either screen), the SizedBox collapses to the parent's max and the
/// `MarkdownBody` + `InkOverlay` reflow / resize at that narrower
/// width. Strokes captured at one width replayed at another land on
/// different words.
///
/// ## How it locks
///
/// `OverflowBox(maxWidth=minWidth=kAnnotatedContentWidth)` forces the
/// child to exactly the canonical width, overriding the parent's
/// constraint. `Transform.scale(scale, alignment: topCenter)` zooms
/// the canonical box so its rendered width matches the viewport
/// (upscale in landscape, downscale in portrait). `ClipRect` trims any
/// 1-px anti-alias bleed past the viewport edge.
///
/// ## Pointer-event invariant
///
/// `Transform` participates in hit-testing: Flutter inverts the scale
/// matrix when a pointer event descends into the subtree, so
/// `event.localPosition` at the `InkOverlay` Listener reports
/// **canonical (unscaled) coordinates** whether the user taps in
/// landscape (scale > 1) or portrait (scale < 1). Stored stroke paths
/// therefore live in one coordinate space across every screen /
/// orientation combo.
///
/// ## Vertical scroll
///
/// [SingleChildScrollView] wraps the child so long markdown can scroll.
/// The scroll extent and gesture deltas are all in canonical coords
/// via the transform-invert path, so a finger dragging N physical
/// pixels scrolls N physical pixels of content regardless of `scale`.
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
        // Zoom-to-fill: scale the canonical box so its rendered width
        // equals the viewport width. Scales up in landscape, down in
        // portrait. A tiny floor avoids divide-by-zero in zero-width
        // first-frame edge cases (tests, route transitions).
        final scale = maxW <= 0 ? 1.0 : maxW / kAnnotatedContentWidth;
        // Canonical-space height of the scroll viewport. After
        // Transform.scale this renders at exactly [maxH].
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
