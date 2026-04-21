import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../domain/entities/pointer_sample.dart';
import '../../../domain/entities/stroke.dart';
import '../../../domain/entities/stroke_group.dart';
import 'ink_overlay_painter.dart';
import 'pointer_event_mapper.dart';

/// Phase of a pointer interaction reported to the [InkOverlay]'s parent.
///
/// The widget reports phases faithfully; policy (e.g. "only stylus creates
/// strokes") lives in the controller / session, not here. Cancel is a
/// separate phase so the parent can decide whether to drop or commit an
/// in-flight stroke (T7's call).
enum InkPointerPhase { down, move, up, cancel }

/// Pure UI shell: translates Flutter [PointerEvent]s into domain
/// [PointerSample]s and forwards them to [onSample] while painting both
/// committed [groups] and an in-progress stroke fed by [activeStroke].
///
/// No Riverpod here — T7 reads controller state in a parent widget and
/// passes the callback + lists into this one. Keeping the widget pure
/// makes it trivially reusable and testable.
class InkOverlay extends StatefulWidget {
  const InkOverlay({
    required this.groups,
    required this.activeStroke,
    required this.currentStrokeColor,
    required this.currentStrokeWidth,
    required this.onSample,
    required this.nowProvider,
    required this.hitTestBehavior,
    this.currentStrokeOpacity = Stroke.kDefaultStrokeOpacity,
    super.key,
  });

  final List<StrokeGroup> groups;
  final ValueListenable<List<Offset>> activeStroke;
  final Color currentStrokeColor;
  final double currentStrokeWidth;

  /// Alpha applied to the in-progress stroke preview — matches the
  /// opacity that [AnnotationSession] will stamp onto the [Stroke] on
  /// commit, so the live preview doesn't shift when the stroke is
  /// committed (highlighter preview stays 0.35, pen stays 0.9).
  final double currentStrokeOpacity;
  final void Function(InkPointerPhase phase, PointerSample sample) onSample;

  /// Clock seam. T7 wires `ref.read(clockProvider).now`; the widget stays
  /// free of any domain port so it's reusable across screens.
  final DateTime Function() nowProvider;

  /// Forwarded to the underlying [Listener] so parents can pick between
  /// opaque (capture all events) and translucent (let siblings hit-test
  /// first) behavior.
  final HitTestBehavior hitTestBehavior;

  @override
  State<InkOverlay> createState() => _InkOverlayState();
}

class _InkOverlayState extends State<InkOverlay> {
  static const _mapper = PointerEventMapper();

  void _dispatch(InkPointerPhase phase, PointerEvent event) {
    final sample = _mapper.toSample(event, widget.nowProvider());
    if (sample == null) {
      // Non-finite coordinates. Drop silently — domain would throw.
      return;
    }
    widget.onSample(phase, sample);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: widget.hitTestBehavior,
      onPointerDown: (e) => _dispatch(InkPointerPhase.down, e),
      onPointerMove: (e) => _dispatch(InkPointerPhase.move, e),
      onPointerUp: (e) => _dispatch(InkPointerPhase.up, e),
      onPointerCancel: (e) => _dispatch(InkPointerPhase.cancel, e),
      child: CustomPaint(
        painter: InkOverlayPainter(
          groups: widget.groups,
          activeStroke: widget.activeStroke,
          activeStrokeColor: widget.currentStrokeColor,
          activeStrokeWidth: widget.currentStrokeWidth,
          activeStrokeOpacity: widget.currentStrokeOpacity,
        ),
        size: Size.infinite,
      ),
    );
  }
}
