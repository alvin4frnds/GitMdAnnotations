import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers/spec_providers.dart';
import '../../../domain/entities/job_ref.dart';
import '../../../domain/entities/spec_file.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';

/// Renders the full spec markdown behind the ink overlay so the user can
/// annotate every heading, paragraph, bullet, and code block — not just a
/// pre-canned "Open questions / Assumptions" extract. Reads through
/// `specFileProvider(jobRef)` so the content stays in sync with what the
/// Spec Reader and Review panel show.
class MarkdownStub extends ConsumerWidget {
  const MarkdownStub({this.jobRef, super.key});

  final JobRef? jobRef;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final job = jobRef;
    if (job == null) {
      return Text(
        'No job selected — open a spec from the job list to annotate it.',
        style: TextStyle(color: t.textMuted, fontSize: 13),
      );
    }
    final async = ref.watch(specFileProvider(job));
    return async.when(
      loading: () => Text(
        'Loading spec…',
        style: TextStyle(color: t.textMuted, fontSize: 13),
      ),
      error: (e, _) => Text(
        "Couldn't load the spec: $e",
        style: TextStyle(color: t.statusDanger, fontSize: 13),
      ),
      data: (spec) {
        if (spec == null) {
          return Text(
            'No workdir — pick a repo from the RepoPicker first.',
            style: TextStyle(color: t.textMuted, fontSize: 13),
          );
        }
        return _SpecMarkdown(spec: spec);
      },
    );
  }
}

class _SpecMarkdown extends StatelessWidget {
  const _SpecMarkdown({required this.spec});
  final SpecFile spec;

  @override
  Widget build(BuildContext context) {
    return MarkdownBody(
      data: spec.contents,
      shrinkWrap: true,
      selectable: false,
      styleSheet: _styleSheet(context),
    );
  }

  MarkdownStyleSheet _styleSheet(BuildContext context) {
    final t = context.tokens;
    final base = MarkdownStyleSheet.fromTheme(Theme.of(context));
    return base.copyWith(
      h1: TextStyle(
        color: t.textPrimary,
        fontFamily: 'Inter',
        fontSize: 26,
        fontWeight: FontWeight.w700,
        height: 1.25,
        letterSpacing: -0.3,
      ),
      h1Padding: const EdgeInsets.only(bottom: 10),
      h2: TextStyle(
        color: t.textPrimary,
        fontFamily: 'Inter',
        fontSize: 18,
        fontWeight: FontWeight.w600,
        height: 1.3,
      ),
      h2Padding: const EdgeInsets.only(top: 18, bottom: 6),
      h3: TextStyle(
        color: t.textPrimary,
        fontFamily: 'Inter',
        fontSize: 15,
        fontWeight: FontWeight.w600,
        height: 1.35,
      ),
      h3Padding: const EdgeInsets.only(top: 14, bottom: 4),
      p: TextStyle(
        color: t.textPrimary,
        fontFamily: 'Inter',
        fontSize: 14,
        height: 1.7,
      ),
      pPadding: const EdgeInsets.only(bottom: 6),
      listBullet: TextStyle(color: t.textPrimary, fontSize: 14, height: 1.55),
      code: appMono(context, size: 12.5, color: t.textPrimary)
          .copyWith(backgroundColor: t.surfaceSunken),
      codeblockDecoration: BoxDecoration(
        color: t.surfaceSunken,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: t.borderSubtle),
      ),
      codeblockPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      blockquote: TextStyle(color: t.textMuted, fontSize: 14, height: 1.55),
      blockquoteDecoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: t.borderSubtle, width: 3),
        ),
      ),
      blockquotePadding: const EdgeInsets.only(left: 12),
    );
  }
}
