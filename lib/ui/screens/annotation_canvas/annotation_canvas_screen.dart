import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/controllers/review_controller.dart';
import '../../../app/controllers/review_orchestrator.dart';
import '../../../app/providers/annotation_providers.dart';
import '../../../app/providers/spec_providers.dart';
import '../../../domain/entities/anchor.dart';
import '../../../domain/entities/ink_tool.dart';
import '../../../domain/entities/job_ref.dart';
import '../../../domain/entities/pointer_sample.dart';
import '../../../domain/entities/stroke.dart';
import '../../theme/tokens.dart';
import '../../widgets/ink_overlay/ink_overlay.dart';
import '../review_panel/review_panel_screen.dart';
import '../submit_confirmation/submit_confirmation_screen.dart';
import 'left_rail.dart';
import 'main_content.dart';
import 'top_chrome.dart';

/// Screen 5 from the mockups — pen annotation overlay, wired to
/// [annotationControllerProvider]. Receives a [JobRef] so the provider
/// family scopes state per-job per IMPLEMENTATION.md §2.2.
///
/// Composition is split across sibling files (`top_chrome.dart`,
/// `left_rail.dart`, `main_content.dart`, `markdown_stub.dart`) to keep
/// each under the §2.6 200-line cap. This file owns the pointer-phase
/// policy (stylus creates strokes; touch is dropped) and the
/// `_activeStrokeNotifier` that drives the in-progress stroke paint.
class AnnotationCanvasScreen extends ConsumerStatefulWidget {
  const AnnotationCanvasScreen({required this.jobRef, super.key});

  final JobRef jobRef;

  @override
  ConsumerState<AnnotationCanvasScreen> createState() =>
      _AnnotationCanvasScreenState();
}

class _AnnotationCanvasScreenState
    extends ConsumerState<AnnotationCanvasScreen> {
  /// Drives the active (in-progress) stroke paint. `InkOverlayPainter`
  /// subscribes via `super(repaint: activeStroke)` so the painter
  /// re-issues on every sample without rebuilding the screen tree —
  /// critical for the NFR-1 <25 ms ink latency budget (§2.4).
  final _activeStrokeNotifier = ValueNotifier<List<Offset>>(const []);

  /// Tracks whether the current pointer-down was accepted (kind belongs
  /// to [allowedPointerKindsProvider]) so subsequent move/up samples can
  /// be routed correctly even if the controller's palm rejection would
  /// already drop non-allowed samples.
  bool _capturingPointer = false;

  /// Flipped `true` after the first frame once the theme-appropriate
  /// default ink color has been pushed into the controller. Without
  /// this the canvas would keep the controller's theme-agnostic default
  /// (`#111111`) which reads as near-black on both light and dark
  /// surfaces. The first-frame injection only runs when the controller
  /// is still at that default, so a user's explicit color choice is
  /// never clobbered by a route rebuild.
  bool _defaultInkApplied = false;

  // TODO(markdown-anchor): derive real line from tap Offset once the
  // MarkdownRenderer owns a line-position index (IMPLEMENTATION.md §4.4).
  // Until then every stroke is anchored to line 1, but we stamp the REAL
  // spec source SHA so `CommitPlanner._assertAnchorsMatchSource` accepts
  // the submit. Previously we sent `sourceSha: ''` and every submit blew
  // up with `CommitPlannerAnchorShaMismatch`.
  Anchor _placeholderAnchor() {
    final sha = ref.read(specFileProvider(widget.jobRef)).value?.sha ?? '';
    return MarkdownAnchor(lineNumber: 1, sourceSha: sha);
  }

  @override
  void dispose() {
    _activeStrokeNotifier.dispose();
    super.dispose();
  }

  void _onSample(InkPointerPhase phase, PointerSample sample) {
    final controller =
        ref.read(annotationControllerProvider(widget.jobRef).notifier);
    final allowed = ref.read(allowedPointerKindsProvider);
    final drawingEnabled =
        ref.read(annotationControllerProvider(widget.jobRef)).drawingEnabled;
    switch (phase) {
      case InkPointerPhase.down:
        if (sample.kind == PointerKind.stylus &&
            (sample.buttons & kPrimaryStylusButton) != 0) {
          // Barrel button held on tap — treat as undo, not a stroke.
          // Works in both pen and pan modes; the button itself is an
          // unambiguous stylus signal. `_capturingPointer` stays
          // false, so any follow-up move/up samples from this pointer
          // are silently dropped by the guards below.
          controller.undo();
          return;
        }
        if (!drawingEnabled) {
          // Pan mode — user is viewing, not annotating. Drop the event
          // so the underlying content can pan/scroll naturally.
          return;
        }
        if (!allowed.contains(sample.kind)) {
          // Non-allowed down: controller drops it (palm rejection). We
          // leave the notifier empty and flip no capture flag.
          return;
        }
        _capturingPointer = true;
        _activeStrokeNotifier.value = [Offset(sample.x, sample.y)];
        controller.beginStroke(sample, anchor: _placeholderAnchor());
      case InkPointerPhase.move:
        if (!_capturingPointer || !allowed.contains(sample.kind)) {
          return;
        }
        _activeStrokeNotifier.value = [
          ..._activeStrokeNotifier.value,
          Offset(sample.x, sample.y),
        ];
        controller.extendStroke(sample);
      case InkPointerPhase.up:
        if (!_capturingPointer || !allowed.contains(sample.kind)) {
          return;
        }
        _capturingPointer = false;
        controller.endStroke(sample);
        // Committed stroke now renders from state.groups; drop the
        // in-progress sample list.
        _activeStrokeNotifier.value = const [];
      case InkPointerPhase.cancel:
        if (!_capturingPointer) {
          return;
        }
        _capturingPointer = false;
        controller.endStroke(sample);
        _activeStrokeNotifier.value = const [];
    }
  }

  void _undo() =>
      ref.read(annotationControllerProvider(widget.jobRef).notifier).undo();

  void _redo() =>
      ref.read(annotationControllerProvider(widget.jobRef).notifier).redo();

  void _openReviewPanel() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          body: ReviewPanelScreen(jobRef: widget.jobRef),
        ),
      ),
    );
  }

  Future<void> _submitReview() async {
    final orchestrator = ReviewOrchestrator(ref.read);
    final outcome = await orchestrator.prepare(widget.jobRef);
    if (!mounted) return;
    switch (outcome) {
      case ReviewOrchestratorSignInRequired():
        _toast('Sign in required to submit');
      case ReviewOrchestratorSpecUnavailable():
        _toast('Spec unavailable - reopen the job');
      case ReviewOrchestratorReady(
          :final source,
          :final questions,
          :final strokeGroups,
          :final identity,
        ):
        final result = await showDialog<ReviewSubmission>(
          context: context,
          builder: (_) => SubmitConfirmationScreen(
            jobRef: widget.jobRef,
            source: source,
            questions: questions,
            strokeGroups: strokeGroups,
            identity: identity,
          ),
        );
        if (!mounted || result == null) return;
        switch (result) {
          case ReviewSubmissionSuccess():
            _toast('Review committed locally. Push on next Sync Up.');
          case ReviewSubmissionFailure(:final error):
            _toast('Submit failed: $error');
          case ReviewSubmissionIdle() || ReviewSubmissionInProgress():
            break;
        }
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final state = ref.watch(annotationControllerProvider(widget.jobRef));
    if (!_defaultInkApplied && state.color == '#111111') {
      _defaultInkApplied = true;
      final brightness = Theme.of(context).brightness;
      // Light mode → red (inkRed); dark mode → yellow (statusWarning).
      final defaultColor =
          brightness == Brightness.dark ? t.statusWarning : t.inkRed;
      final hex = _hexFromColor(defaultColor);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final live =
            ref.read(annotationControllerProvider(widget.jobRef));
        if (live.color == '#111111') {
          ref
              .read(annotationControllerProvider(widget.jobRef).notifier)
              .setColor(hex);
        }
      });
    }
    // Preview styling mirrors what AnnotationSession._commit will stamp
    // onto the Stroke on pointer-up, so the in-progress preview looks
    // identical to the committed stroke (no color/width/opacity pop).
    // Kept in sync with `AnnotationSession._widthFor` / `_opacityFor`.
    final strokeColor = _colorFromHex(state.color) ?? t.inkRed;
    final strokeWidth = state.tool == InkTool.highlighter ? 16.0 : 2.0;
    final strokeOpacity = state.tool == InkTool.highlighter
        ? 0.35
        : Stroke.kDefaultStrokeOpacity;
    return Container(
      color: t.surfaceBackground,
      child: Column(
        children: [
          AnnotationTopChrome(
            jobRef: widget.jobRef,
            onUndo: _undo,
            onRedo: _redo,
            onOpenReviewPanel: _openReviewPanel,
            onSubmitReview: _submitReview,
          ),
          Container(height: 1, color: t.borderSubtle),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AnnotationLeftRail(jobRef: widget.jobRef),
                Container(width: 1, color: t.borderSubtle),
                Expanded(
                  child: AnnotationMainContent(
                    jobRef: widget.jobRef,
                    groups: state.groups,
                    activeStroke: _activeStrokeNotifier,
                    currentStrokeColor: strokeColor,
                    currentStrokeWidth: strokeWidth,
                    currentStrokeOpacity: strokeOpacity,
                    drawingEnabled: state.drawingEnabled,
                    hasActiveStylusStroke: state.hasActiveStroke,
                    onSample: _onSample,
                    nowProvider: ref.read(clockProvider).now,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Formats an opaque [Color] as the `#RRGGBB` string the controller
/// stores. Drops the alpha channel since `AnnotationState.color` is a
/// 7-char sRGB hex.
String _hexFromColor(Color color) {
  final r = ((color.r * 255.0).round() & 0xff).toRadixString(16).padLeft(2, '0');
  final g = ((color.g * 255.0).round() & 0xff).toRadixString(16).padLeft(2, '0');
  final b = ((color.b * 255.0).round() & 0xff).toRadixString(16).padLeft(2, '0');
  return '#${r.toUpperCase()}${g.toUpperCase()}${b.toUpperCase()}';
}

/// Parses the `#RRGGBB` hex stored in `AnnotationState.color` into an
/// opaque [Color]. Returns `null` on malformed input so the caller can
/// fall back to a safe theme default (shouldn't happen — the palette
/// widgets only dispatch valid 7-char hex).
Color? _colorFromHex(String hex) {
  if (hex.length != 7 || !hex.startsWith('#')) return null;
  final v = int.tryParse(hex.substring(1), radix: 16);
  if (v == null) return null;
  return Color(0xFF000000 | v);
}
