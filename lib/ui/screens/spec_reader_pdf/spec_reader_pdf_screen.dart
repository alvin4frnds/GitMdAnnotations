import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/controllers/review_controller.dart';
import '../../../app/controllers/review_orchestrator.dart';
import '../../../app/providers/annotation_providers.dart';
import '../../../app/providers/pdf_providers.dart';
import '../../../app/providers/spec_providers.dart';
import '../../../domain/entities/anchor.dart';
import '../../../domain/entities/job_ref.dart';
import '../../../domain/entities/pdf_document_handle.dart';
import '../../../domain/entities/pointer_sample.dart';
import '../../../domain/entities/stroke_group.dart';
import '../../theme/tokens.dart';
import '../../widgets/ink_overlay/ink_overlay.dart';
import '../review_panel/review_panel_screen.dart';
import '../submit_confirmation/submit_confirmation_screen.dart';
import 'spec_reader_pdf_chrome.dart';
import 'spec_reader_pdf_pane.dart';
import 'spec_reader_pdf_rail.dart';

/// Screen 4b — PDF spec reader. Mirrors [SpecReaderMdScreen]'s visual
/// chrome (top bar + left rail + main pane) but composes the PDF page
/// view with the live [InkOverlay] tied to
/// [annotationControllerProvider].
///
/// Composition is split across sibling files per §2.6's 200-line cap:
///   * `spec_reader_pdf_chrome.dart`   — top bar + pen tool bar stub.
///   * `spec_reader_pdf_rail.dart`     — left "pages 1..N" rail.
///   * `spec_reader_pdf_pane.dart`     — PdfPageView + InkOverlay stack.
///
/// This file owns the pointer-phase policy (stylus commits strokes;
/// touch is dropped at the overlay) and the `_activeStrokeNotifier` that
/// drives the in-progress stroke paint, matching
/// `AnnotationCanvasScreen`'s pattern exactly.
class SpecReaderPdfScreen extends ConsumerStatefulWidget {
  const SpecReaderPdfScreen({
    required this.filePath,
    this.jobRef,
    super.key,
  });

  final String filePath;

  /// Null when the screen is opened via the repo browser (spec-002
  /// Milestone A — browser flow). When null, the Annotate / Review /
  /// Submit chrome is hidden and the pen-capture pipeline is disabled.
  final JobRef? jobRef;

  @override
  ConsumerState<SpecReaderPdfScreen> createState() =>
      _SpecReaderPdfScreenState();
}

class _SpecReaderPdfScreenState
    extends ConsumerState<SpecReaderPdfScreen> {
  final _activeStrokeNotifier = ValueNotifier<List<Offset>>(const []);
  bool _capturingStylus = false;
  int _visiblePage = 1;

  // TODO(pdf-anchor): derive (page, bbox) in PDF-page coordinates from
  // the PDF page dims + local tap offset; IMPLEMENTATION.md §4.4
  // "anchor_for(page, bbox)". Until then every stroke's bbox is a
  // zero-area rect, but the sourceSha is the real PDF content SHA so
  // `CommitPlanner._assertAnchorsMatchSource` accepts the submit.
  Anchor _placeholderAnchor() {
    final job = widget.jobRef!;
    final sha = ref.read(specFileProvider(job)).value?.sha ?? '';
    return PdfAnchor(
      page: _visiblePage,
      bbox: const Rect(left: 0, top: 0, right: 0, bottom: 0),
      sourceSha: sha,
    );
  }

  @override
  void dispose() {
    _activeStrokeNotifier.dispose();
    super.dispose();
  }

  void _onSample(InkPointerPhase phase, PointerSample sample) {
    final job = widget.jobRef;
    if (job == null) return; // browser flow: no annotation pipeline
    final ctrl = ref.read(annotationControllerProvider(job).notifier);
    final drawingEnabled =
        ref.read(annotationControllerProvider(job)).drawingEnabled;
    switch (phase) {
      case InkPointerPhase.down:
        if (sample.kind == PointerKind.stylus &&
            (sample.buttons & kPrimaryStylusButton) != 0) {
          // Barrel button held on tap — undo, not a stroke. Mirrors
          // the annotation canvas behavior so the gesture works in
          // both readers. `_capturingStylus` stays false so any
          // stray move/up samples are dropped by the guards below.
          ctrl.undo();
          return;
        }
        if (!drawingEnabled) return; // Pan mode
        if (sample.kind != PointerKind.stylus) return;
        _capturingStylus = true;
        _activeStrokeNotifier.value = [Offset(sample.x, sample.y)];
        ctrl.beginStroke(sample, anchor: _placeholderAnchor());
      case InkPointerPhase.move:
        if (!_capturingStylus || sample.kind != PointerKind.stylus) return;
        _activeStrokeNotifier.value = [
          ..._activeStrokeNotifier.value,
          Offset(sample.x, sample.y),
        ];
        ctrl.extendStroke(sample);
      case InkPointerPhase.up:
        if (!_capturingStylus || sample.kind != PointerKind.stylus) return;
        _capturingStylus = false;
        ctrl.endStroke(sample);
        _activeStrokeNotifier.value = const [];
      case InkPointerPhase.cancel:
        if (!_capturingStylus) return;
        _capturingStylus = false;
        ctrl.endStroke(sample);
        _activeStrokeNotifier.value = const [];
    }
  }

  void _undo() {
    final job = widget.jobRef;
    if (job == null) return;
    ref.read(annotationControllerProvider(job).notifier).undo();
  }

  void _redo() {
    final job = widget.jobRef;
    if (job == null) return;
    ref.read(annotationControllerProvider(job).notifier).redo();
  }

  void _openReviewPanel() {
    final job = widget.jobRef;
    if (job == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          body: ReviewPanelScreen(jobRef: job),
        ),
      ),
    );
  }

  Future<void> _submitReview() async {
    final job = widget.jobRef;
    if (job == null) return;
    final orchestrator = ReviewOrchestrator(ref.read);
    final outcome = await orchestrator.prepare(job);
    if (!mounted) return;
    switch (outcome) {
      case ReviewOrchestratorSignInRequired():
        _toast('Sign in required to submit');
      case ReviewOrchestratorSpecUnavailable():
        _toast('Spec unavailable — reopen the job');
      case ReviewOrchestratorReady(
          :final source,
          :final questions,
          :final strokeGroups,
          :final identity,
        ):
        final result = await showDialog<ReviewSubmission>(
          context: context,
          builder: (_) => SubmitConfirmationScreen(
            jobRef: job,
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
    final job = widget.jobRef;
    // Browser flow has no job-scoped annotation state; render an empty
    // group list so the pane still composes the InkOverlay stack at
    // zero cost.
    final groups = job == null
        ? const <StrokeGroup>[]
        : ref.watch(annotationControllerProvider(job)).groups;
    final docAsync =
        ref.watch(pdfDocumentNotifierProvider(widget.filePath));
    return Container(
      color: t.surfaceBackground,
      child: Column(
        children: [
          SpecReaderPdfChrome(
            jobRef: job,
            jobId: job?.jobId ?? _basename(widget.filePath),
            onUndo: _undo,
            onRedo: _redo,
            onOpenReviewPanel: _openReviewPanel,
            onSubmit: _submitReview,
          ),
          Container(height: 1, color: t.borderSubtle),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SpecReaderPdfRail(
                  pageCount: docAsync.maybeWhen(
                    data: (h) => h.pageCount,
                    orElse: () => 0,
                  ),
                  currentPage: _visiblePage,
                ),
                Container(width: 1, color: t.borderSubtle),
                Expanded(
                  child: _buildMainPane(docAsync, groups),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _basename(String path) {
    final slash = path.lastIndexOf(RegExp(r'[/\\]'));
    return slash < 0 ? path : path.substring(slash + 1);
  }

  Widget _buildMainPane(
    AsyncValue<PdfDocumentHandle> docAsync,
    List groups,
  ) {
    final t = context.tokens;
    return docAsync.when(
      data: (handle) => SpecReaderPdfPane(
        filePath: widget.filePath,
        handle: handle,
        groups: List.from(groups),
        activeStroke: _activeStrokeNotifier,
        onSample: _onSample,
        nowProvider: ref.read(clockProvider).now,
        onVisiblePageChanged: (p) => setState(() => _visiblePage = p),
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Failed to open PDF: $e',
            style: TextStyle(color: t.textPrimary, fontSize: 14),
          ),
        ),
      ),
    );
  }
}
