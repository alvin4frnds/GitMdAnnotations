import 'package:flutter/material.dart';

import '../../../domain/services/open_question_extractor.dart';
import '../../theme/tokens.dart';

/// A single question card in the typed review pane: shows the question
/// body and a borderless multi-line answer field bound to a caller-
/// supplied [TextEditingController].
class QuestionCard extends StatelessWidget {
  final OpenQuestion question;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  const QuestionCard({
    required this.question,
    required this.controller,
    required this.onChanged,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      decoration: BoxDecoration(
        color: t.surfaceElevated,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: t.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${question.id}: ${question.body}',
            style: TextStyle(
              color: t.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: controller,
            onChanged: onChanged,
            maxLines: null,
            minLines: 2,
            style: TextStyle(
              color: t.textPrimary,
              fontSize: 13,
              height: 1.4,
            ),
            cursorColor: t.accentPrimary,
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 6),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: t.accentPrimary, width: 1.2),
              ),
              hintText: 'Your answer...',
              hintStyle: TextStyle(
                color: t.textMuted,
                fontSize: 13,
                height: 1.4,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Free-form notes field at the bottom of the typed review pane.
class FreeFormField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  const FreeFormField({
    required this.controller,
    required this.onChanged,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: t.surfaceElevated,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: t.borderSubtle),
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        maxLines: null,
        minLines: 3,
        style: TextStyle(color: t.textPrimary, fontSize: 13, height: 1.45),
        cursorColor: t.accentPrimary,
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 4),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: t.accentPrimary, width: 1.2),
          ),
          hintText: 'Additional notes...',
          hintStyle: TextStyle(
            color: t.textMuted,
            fontSize: 13,
            fontStyle: FontStyle.italic,
          ),
        ),
      ),
    );
  }
}
