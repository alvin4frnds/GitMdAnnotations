import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/controllers/review_controller.dart';
import '../../../app/controllers/review_orchestrator.dart';
import '../../../app/providers/spec_providers.dart';
import '../../../domain/entities/job_ref.dart';
import '../../../domain/entities/spec_file.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../annotation_canvas/annotation_canvas_screen.dart';
import '../review_panel/review_panel_screen.dart';
import '../submit_confirmation/submit_confirmation_screen.dart';
import 'md_image_resolver.dart';

/// Spec reader — markdown view.
///
/// Two entry points:
///   * Job flow: constructed with [jobRef]; reads via
///     `specFileProvider(jobRef)` → `SpecRepository.loadSpec`. Annotate /
///     Review panel / Submit chrome is enabled.
///   * Browser flow ([SpecReaderMdScreen.fromPath]): constructed with an
///     absolute filesystem path; reads via `specFileByPathProvider` →
///     `FileSystemPort.readString`. Annotate / Submit chrome is hidden
///     because the file isn't a tracked spec.
///
/// Left nav rail lists the document's H1/H2 outline extracted from the
/// loaded markdown.
class SpecReaderMdScreen extends StatelessWidget {
  const SpecReaderMdScreen({this.jobRef, super.key}) : filePath = null;

  /// Browser-flow entry: open any `.md` / `.markdown` file by absolute
  /// path. [jobRef] is null so job-flow chrome is gated off.
  const SpecReaderMdScreen.fromPath({
    required String this.filePath,
    super.key,
  }) : jobRef = null;

  final JobRef? jobRef;
  final String? filePath;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return ColoredBox(
      color: t.surfaceBackground,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _TopChrome(jobRef: jobRef, filePath: filePath),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _OnThisPageRail(jobRef: jobRef, filePath: filePath),
                Expanded(
                  child: _MarkdownPane(jobRef: jobRef, filePath: filePath),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Top chrome (52px)
// -----------------------------------------------------------------------------

class _TopChrome extends ConsumerWidget {
  const _TopChrome({required this.jobRef, required this.filePath});
  final JobRef? jobRef;
  final String? filePath;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final hasJob = jobRef != null;
    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: t.surfaceElevated,
        border: Border(bottom: BorderSide(color: t.borderSubtle)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Flexible(
            child: _FileBreadcrumb(jobRef: jobRef, filePath: filePath),
          ),
          const Spacer(),
          if (hasJob) ...[
            const _PenToolBar(),
            const SizedBox(width: 12),
            _GhostButton(
              label: 'Annotate',
              trailing: Icons.edit_outlined,
              onPressed: () => _openCanvas(context),
            ),
            const SizedBox(width: 8),
            _GhostButton(
              label: 'Review panel',
              trailing: Icons.chevron_right,
              onPressed: () => _openReviewPanel(context),
            ),
            const SizedBox(width: 8),
            _PrimaryButton(
              label: 'Submit',
              onPressed: () => _submit(context, ref),
            ),
          ],
        ],
      ),
    );
  }

  void _openCanvas(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          body: AnnotationCanvasScreen(jobRef: jobRef!),
        ),
      ),
    );
  }

  void _openReviewPanel(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          body: ReviewPanelScreen(jobRef: jobRef!),
        ),
      ),
    );
  }

  Future<void> _submit(BuildContext context, WidgetRef ref) async {
    final orchestrator = ReviewOrchestrator(ref.read);
    final outcome = await orchestrator.prepare(jobRef!);
    if (!context.mounted) return;
    switch (outcome) {
      case ReviewOrchestratorSignInRequired():
        _toast(context, 'Sign in required to submit');
      case ReviewOrchestratorSpecUnavailable():
        _toast(context, 'Spec unavailable — reopen the job');
      case ReviewOrchestratorReady(
          :final source,
          :final questions,
          :final strokeGroups,
          :final identity,
        ):
        final result = await showDialog<ReviewSubmission>(
          context: context,
          builder: (_) => SubmitConfirmationScreen(
            jobRef: jobRef!,
            source: source,
            questions: questions,
            strokeGroups: strokeGroups,
            identity: identity,
          ),
        );
        if (!context.mounted || result == null) return;
        switch (result) {
          case ReviewSubmissionSuccess():
            _toast(context, 'Review committed locally. Push on next Sync Up.');
          case ReviewSubmissionFailure(:final error):
            _toast(context, 'Submit failed: $error');
          case ReviewSubmissionIdle() || ReviewSubmissionInProgress():
            break;
        }
    }
  }

  void _toast(BuildContext context, String message) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
    );
  }
}

class _FileBreadcrumb extends ConsumerWidget {
  const _FileBreadcrumb({required this.jobRef, required this.filePath});
  final JobRef? jobRef;
  final String? filePath;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final job = jobRef;
    final path = filePath;
    final filename = job != null
        ? ref.watch(specFileProvider(job)).value?.path.split('/').last ??
            '02-spec.md'
        : path != null
            ? path.replaceAll('\\', '/').split('/').last
            : '02-spec.md';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          filename,
          style: appMono(
            context,
            size: 13,
            weight: FontWeight.w600,
            color: t.textPrimary,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '·',
          style: TextStyle(color: t.textMuted, fontSize: 13),
        ),
        const SizedBox(width: 8),
        Text(
          job?.jobId ?? 'spec-auth-flow-totp',
          style: appMono(context, size: 13, color: t.textMuted),
        ),
      ],
    );
  }
}

class _PenToolBar extends StatelessWidget {
  const _PenToolBar();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: t.surfaceElevated,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: t.borderSubtle),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ToolIcon(icon: Icons.visibility_outlined, selected: true),
          _ToolIcon(icon: Icons.edit_outlined),
          _ToolIcon(icon: Icons.format_color_fill_outlined),
          _ToolIcon(icon: Icons.auto_fix_high_outlined),
          const SizedBox(width: 6),
          Container(width: 1, height: 20, color: t.borderSubtle),
          const SizedBox(width: 8),
          _ColorDot(color: t.inkRed),
          _ColorDot(color: t.inkBlue),
          _ColorDot(color: t.inkGreen),
          _ColorDot(color: t.statusWarning),
          _ColorDot(color: t.textPrimary),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

class _ToolIcon extends StatelessWidget {
  final IconData icon;
  final bool selected;
  const _ToolIcon({required this.icon, this.selected = false});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      width: 28,
      height: 28,
      margin: const EdgeInsets.symmetric(horizontal: 1),
      decoration: BoxDecoration(
        color: selected ? t.accentSoftBg : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
      ),
      alignment: Alignment.center,
      child: Icon(
        icon,
        size: 16,
        color: selected ? t.accentPrimary : t.textMuted,
      ),
    );
  }
}

class _ColorDot extends StatelessWidget {
  final Color color;
  const _ColorDot({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 12,
      height: 12,
      margin: const EdgeInsets.symmetric(horizontal: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.35),
        shape: BoxShape.circle,
      ),
    );
  }
}

class _GhostButton extends StatelessWidget {
  final String label;
  final IconData? trailing;
  final VoidCallback onPressed;
  const _GhostButton(
      {required this.label, this.trailing, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: t.textPrimary,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: t.borderSubtle),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 4),
            Icon(trailing, size: 16, color: t.textMuted),
          ],
        ],
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  const _PrimaryButton({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: t.accentPrimary,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Left rail — "On this page"
// -----------------------------------------------------------------------------

/// Parses the top-level (H1/H2) headings out of the loaded spec file and
/// renders them as an outline. When no [jobRef] is passed (mockup
/// surface) or the spec hasn't loaded yet, shows a muted placeholder so
/// the chrome doesn't reflow.
class _OnThisPageRail extends ConsumerWidget {
  const _OnThisPageRail({required this.jobRef, required this.filePath});
  final JobRef? jobRef;
  final String? filePath;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final List<String> headings;
    final job = jobRef;
    final path = filePath;
    if (job != null) {
      final spec = ref.watch(specFileProvider(job)).value;
      headings = spec == null
          ? const ['Loading...']
          : _extractHeadings(spec.contents);
    } else if (path != null) {
      final spec = ref.watch(specFileByPathProvider(path)).value;
      headings = spec == null
          ? const ['Loading...']
          : _extractHeadings(spec.contents);
    } else {
      headings = const ['Overview', 'Goals', 'Open questions'];
    }
    return Container(
      width: 192,
      decoration: BoxDecoration(
        color: t.surfaceElevated,
        border: Border(right: BorderSide(color: t.borderSubtle)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 20, 12, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'ON THIS PAGE',
            style: TextStyle(
              color: t.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 12),
          if (headings.isEmpty)
            Text(
              '(no headings)',
              style: TextStyle(color: t.textMuted, fontSize: 12),
            )
          else
            for (var i = 0; i < headings.length; i++)
              _RailEntry(label: headings[i], current: i == 0),
        ],
      ),
    );
  }
}

class _RailEntry extends StatelessWidget {
  final String label;
  final bool current;
  const _RailEntry({required this.label, this.current = false});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      decoration: BoxDecoration(
        color: current ? t.accentSoftBg : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: current ? t.accentPrimary : t.textPrimary,
          fontSize: 12,
          fontWeight: current ? FontWeight.w600 : FontWeight.w400,
          height: 1.35,
        ),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

/// Extracts `# ` and `## ` headings from [markdown] in document order,
/// stripping the hash markers and any surrounding whitespace. Lines
/// inside fenced code blocks (three backticks) are ignored so a `#`
/// comment in a shell snippet doesn't leak into the outline.
List<String> _extractHeadings(String markdown) {
  final out = <String>[];
  var inFence = false;
  for (final line in markdown.split('\n')) {
    final trimmed = line.trimLeft();
    if (trimmed.startsWith('```')) {
      inFence = !inFence;
      continue;
    }
    if (inFence) continue;
    final m = _headingPattern.firstMatch(line);
    if (m != null) {
      final text = m.group(2)?.trim() ?? '';
      if (text.isNotEmpty) out.add(text);
    }
  }
  return out;
}

final _headingPattern = RegExp(r'^(#{1,2})\s+(.+?)\s*$');

// -----------------------------------------------------------------------------
// Main markdown pane — loads real content via specFileProvider + renders
// through flutter_markdown.
// -----------------------------------------------------------------------------

class _MarkdownPane extends ConsumerWidget {
  const _MarkdownPane({required this.jobRef, required this.filePath});
  final JobRef? jobRef;
  final String? filePath;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final job = jobRef;
    final path = filePath;
    if (job != null) {
      final async = ref.watch(specFileProvider(job));
      return async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _MuteMessage(
          message: "Couldn't load the spec.",
          submessage: e.toString(),
          isError: true,
        ),
        data: (spec) => spec == null
            ? const _MuteMessage(
                message: 'No workdir.',
                submessage: 'Pick a repo from the RepoPicker first.',
              )
            : _MarkdownBodyView(spec: spec),
      );
    }
    if (path != null) {
      final async = ref.watch(specFileByPathProvider(path));
      return async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _MuteMessage(
          message: "Couldn't open the file.",
          submessage: e.toString(),
          isError: true,
        ),
        data: (spec) => _MarkdownBodyView(spec: spec),
      );
    }
    return const _MuteMessage(
      message: 'No job selected.',
      submessage: 'Pick a job from the JobList to view its spec.',
    );
  }
}

class _MarkdownBodyView extends StatelessWidget {
  const _MarkdownBodyView({required this.spec});
  final SpecFile spec;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return ColoredBox(
      color: t.surfaceBackground,
      child: Markdown(
        data: spec.contents,
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 32),
        shrinkWrap: false,
        selectable: false,
        styleSheet: _styleSheet(context),
        sizedImageBuilder: (config) => resolveInlineImage(
          uri: config.uri,
          specPath: spec.path,
          context: context,
          title: config.title,
          alt: config.alt,
        ),
      ),
    );
  }

  MarkdownStyleSheet _styleSheet(BuildContext context) {
    final t = context.tokens;
    final base = MarkdownStyleSheet.fromTheme(Theme.of(context));
    return base.copyWith(
      h1: TextStyle(
        color: t.textPrimary,
        fontFamily: 'Inter',
        fontSize: 28,
        fontWeight: FontWeight.w700,
        height: 1.25,
        letterSpacing: -0.4,
      ),
      h1Padding: const EdgeInsets.only(bottom: 12),
      h2: TextStyle(
        color: t.textPrimary,
        fontFamily: 'Inter',
        fontSize: 20,
        fontWeight: FontWeight.w600,
        height: 1.3,
        letterSpacing: -0.2,
      ),
      h2Padding: const EdgeInsets.only(top: 20, bottom: 8),
      h3: TextStyle(
        color: t.textPrimary,
        fontFamily: 'Inter',
        fontSize: 16,
        fontWeight: FontWeight.w600,
        height: 1.35,
      ),
      h3Padding: const EdgeInsets.only(top: 16, bottom: 6),
      p: TextStyle(
        color: t.textPrimary,
        fontFamily: 'Inter',
        fontSize: 14,
        height: 1.6,
      ),
      pPadding: const EdgeInsets.only(bottom: 8),
      listBullet: TextStyle(color: t.textMuted, fontSize: 14, height: 1.55),
      code: appMono(context, size: 12.5, color: t.textPrimary)
          .copyWith(backgroundColor: t.surfaceSunken),
      codeblockDecoration: BoxDecoration(
        color: t.surfaceSunken,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: t.borderSubtle),
      ),
      codeblockPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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

class _MuteMessage extends StatelessWidget {
  const _MuteMessage({
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
            Icon(
              isError
                  ? Icons.error_outline_rounded
                  : Icons.description_outlined,
              size: 28,
              color: color,
            ),
            const SizedBox(height: 10),
            Text(
              message,
              style: TextStyle(
                color: color,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Text(
                submessage,
                textAlign: TextAlign.center,
                style: TextStyle(color: color, fontSize: 12, height: 1.4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
