import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers/review_providers.dart';
import '../../../domain/entities/job_ref.dart';
import '../../../domain/services/open_question_extractor.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import 'question_card.dart';

/// Right pane of the review screen — typed Q&A + free-form notes, bound
/// to [ReviewController]. Answers are backed by per-question
/// [TextEditingController]s that stay mounted across state rebuilds so
/// the cursor doesn't jump on every keystroke; mutations flow through
/// `setAnswer` / `setFreeFormNotes` which auto-save the draft.
class TypedReviewPane extends ConsumerStatefulWidget {
  const TypedReviewPane({
    required this.jobRef,
    required this.questions,
    super.key,
  });

  final JobRef jobRef;
  final List<OpenQuestion> questions;

  @override
  ConsumerState<TypedReviewPane> createState() => _TypedReviewPaneState();
}

class _TypedReviewPaneState extends ConsumerState<TypedReviewPane> {
  final Map<String, TextEditingController> _answerControllers = {};
  TextEditingController? _notesController;

  @override
  void dispose() {
    for (final c in _answerControllers.values) {
      c.dispose();
    }
    _notesController?.dispose();
    super.dispose();
  }

  TextEditingController _answerFor(String id, String initial) {
    final existing = _answerControllers[id];
    if (existing != null) return existing;
    final c = TextEditingController(text: initial);
    _answerControllers[id] = c;
    return c;
  }

  TextEditingController _notes(String initial) {
    return _notesController ??= TextEditingController(text: initial);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final async = ref.watch(reviewControllerProvider(widget.jobRef));
    final notifier =
        ref.read(reviewControllerProvider(widget.jobRef).notifier);

    return Container(
      decoration: BoxDecoration(
        color: t.surfaceSunken,
        border: Border(left: BorderSide(color: t.borderSubtle)),
      ),
      child: async.when(
        data: (state) => SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Header(jobId: widget.jobRef.jobId),
              const SizedBox(height: 18),
              if (widget.questions.isNotEmpty) ...[
                const _SectionHeader('Answers to open questions'),
                const SizedBox(height: 10),
                for (final q in widget.questions) ...[
                  QuestionCard(
                    question: q,
                    controller: _answerFor(q.id, state.answers[q.id] ?? ''),
                    onChanged: (v) => notifier.setAnswer(q.id, v),
                  ),
                  const SizedBox(height: 12),
                ],
                const SizedBox(height: 10),
              ],
              const _SectionHeader('Free-form notes'),
              const SizedBox(height: 10),
              FreeFormField(
                controller: _notes(state.freeFormNotes),
                onChanged: notifier.setFreeFormNotes,
              ),
            ],
          ),
        ),
        error: (e, _) => Padding(
          padding: const EdgeInsets.all(20),
          child: Text('Failed to load review: $e',
              style: TextStyle(color: t.textMuted)),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String jobId;
  const _Header({required this.jobId});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Row(
      children: [
        Text(
          '03-review.md (draft)',
          style: appMono(
            context,
            size: 12,
            weight: FontWeight.w600,
            color: t.textPrimary,
          ),
        ),
        const Spacer(),
        Text(
          jobId,
          style: appMono(context, size: 11, color: t.textMuted),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        color: t.textMuted,
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.6,
      ),
    );
  }
}
