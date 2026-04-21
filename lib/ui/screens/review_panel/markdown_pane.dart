import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers/annotation_providers.dart';
import '../../../app/providers/spec_providers.dart';
import '../../../domain/entities/job_ref.dart';
import '../../../domain/entities/spec_file.dart';
import '../../../domain/entities/stroke_group.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';

/// Left pane of the review screen — real spec markdown (loaded through
/// `specFileProvider`) plus a small annotations summary sourced from the
/// job's committed stroke groups. No hardcoded "Auth flow — TOTP
/// rollout" body anymore.
class MarkdownPane extends ConsumerWidget {
  const MarkdownPane({required this.jobRef, super.key});

  final JobRef jobRef;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final async = ref.watch(specFileProvider(jobRef));
    final strokeGroups = ref.watch(annotationControllerProvider(jobRef)).groups;
    return Container(
      color: t.surfaceElevated,
      child: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _Mute(
          message: "Couldn't load the spec.",
          submessage: e.toString(),
          isError: true,
        ),
        data: (spec) {
          if (spec == null) {
            return const _Mute(
              message: 'No workdir.',
              submessage: 'Pick a repo from the RepoPicker first.',
            );
          }
          return _Body(spec: spec, strokeGroups: strokeGroups);
        },
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.spec, required this.strokeGroups});
  final SpecFile spec;
  final List<StrokeGroup> strokeGroups;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(40, 28, 40, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MarkdownBody(
            data: spec.contents,
            shrinkWrap: true,
            selectable: false,
            styleSheet: _styleSheet(context),
          ),
          const SizedBox(height: 24),
          Text(
            _annotationSummary(strokeGroups),
            style: TextStyle(color: t.textMuted, fontSize: 11),
          ),
        ],
      ),
    );
  }

  String _annotationSummary(List<StrokeGroup> groups) {
    if (groups.isEmpty) return 'No annotations yet';
    final strokes = groups.fold<int>(0, (sum, g) => sum + g.strokes.length);
    final groupLabel = groups.length == 1 ? 'stroke group' : 'stroke groups';
    final strokeLabel = strokes == 1 ? 'stroke' : 'strokes';
    return '${groups.length} $groupLabel · $strokes $strokeLabel';
  }

  MarkdownStyleSheet _styleSheet(BuildContext context) {
    final t = context.tokens;
    final base = MarkdownStyleSheet.fromTheme(Theme.of(context));
    return base.copyWith(
      h1: TextStyle(
        color: t.textPrimary,
        fontFamily: 'Inter',
        fontSize: 22,
        fontWeight: FontWeight.w700,
        height: 1.25,
        letterSpacing: -0.3,
      ),
      h1Padding: const EdgeInsets.only(bottom: 10),
      h2: TextStyle(
        color: t.textPrimary,
        fontFamily: 'Inter',
        fontSize: 15,
        fontWeight: FontWeight.w700,
        height: 1.3,
      ),
      h2Padding: const EdgeInsets.only(top: 14, bottom: 6),
      h3: TextStyle(
        color: t.textPrimary,
        fontFamily: 'Inter',
        fontSize: 13,
        fontWeight: FontWeight.w600,
        height: 1.35,
      ),
      h3Padding: const EdgeInsets.only(top: 12, bottom: 4),
      p: TextStyle(
        color: t.textPrimary,
        fontFamily: 'Inter',
        fontSize: 12,
        height: 1.55,
      ),
      pPadding: const EdgeInsets.only(bottom: 6),
      listBullet: TextStyle(color: t.textPrimary, fontSize: 12, height: 1.5),
      code: appMono(context, size: 11.5, color: t.textPrimary)
          .copyWith(backgroundColor: t.surfaceSunken),
      codeblockDecoration: BoxDecoration(
        color: t.surfaceSunken,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: t.borderSubtle),
      ),
      codeblockPadding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    );
  }
}

class _Mute extends StatelessWidget {
  const _Mute({
    required this.message,
    required this.submessage,
    this.isError = false,
  });
  final String message;
  final String submessage;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final color = isError ? t.statusDanger : t.textMuted;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              style: TextStyle(
                color: color,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              submessage,
              textAlign: TextAlign.center,
              style: TextStyle(color: color, fontSize: 11, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}
