import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/controllers/review_orchestrator.dart';
import '../../../domain/entities/job_ref.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../annotation_canvas/annotation_canvas_screen.dart';
import '../review_panel/review_panel_screen.dart';
import '../submit_confirmation/submit_confirmation_screen.dart';

/// Spec reader — markdown view (UI spike).
///
/// Pure visual fidelity to the PRD mockup. Left nav rail lists the document's
/// H2/H3 outline, the top chrome hosts the pen-tool bar, and the main pane
/// renders a stubbed markdown document via styled [Text] widgets.
///
/// [jobRef] is accepted for forward compatibility — the real markdown
/// rendering pipeline (M1d) will load the spec file for this job from
/// the `SpecRepository`. The current UI spike still shows hardcoded
/// TOTP rollout copy.
class SpecReaderMdScreen extends StatelessWidget {
  const SpecReaderMdScreen({this.jobRef, super.key});

  final JobRef? jobRef;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return ColoredBox(
      color: t.surfaceBackground,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _TopChrome(jobRef: jobRef),
          const Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _OnThisPageRail(),
                Expanded(child: _MarkdownPane()),
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
  const _TopChrome({required this.jobRef});
  final JobRef? jobRef;

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
          // Left: filename + breadcrumb
          Flexible(child: _FileBreadcrumb()),
          const Spacer(),
          // Middle: pen tool bar
          const _PenToolBar(),
          const SizedBox(width: 12),
          // Annotate → AnnotationCanvasScreen (pen mode).
          _GhostButton(
            label: 'Annotate',
            trailing: Icons.edit_outlined,
            onPressed: hasJob ? () => _openCanvas(context) : () {},
          ),
          const SizedBox(width: 8),
          // Review panel → typed review questions.
          _GhostButton(
            label: 'Review panel',
            trailing: Icons.chevron_right,
            onPressed: hasJob ? () => _openReviewPanel(context) : () {},
          ),
          const SizedBox(width: 8),
          // Submit → ReviewOrchestrator.prepare then commit.
          _PrimaryButton(
            label: 'Submit',
            onPressed: hasJob ? () => _submit(context, ref) : () {},
          ),
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
        await showDialog<bool>(
          context: context,
          builder: (dialogCtx) => SubmitConfirmationScreen(
            jobRef: jobRef!,
            source: source,
            questions: questions,
            strokeGroups: strokeGroups,
            identity: identity,
            onCommitted: (_) => Navigator.of(dialogCtx).pop(true),
          ),
        );
    }
  }

  void _toast(BuildContext context, String message) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
    );
  }
}

class _FileBreadcrumb extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '02-spec.md',
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
          'spec-auth-flow-totp',
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
          // Colored dots — disabled while Read tool is selected.
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
    // Disabled look: dim the dot while Read tool is active.
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
  const _GhostButton({required this.label, this.trailing, required this.onPressed});

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

class _OnThisPageRail extends StatelessWidget {
  const _OnThisPageRail();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
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
          const _RailEntry(label: 'Auth flow — TOTP rollout', current: true),
          const _RailEntry(label: 'Goals'),
          const _RailEntry(label: 'Non-goals'),
          const _RailEntry(label: 'Open questions'),
          const _RailEntry(label: 'Implementation sketch'),
        ],
      ),
    );
  }
}

class _RailEntry extends StatelessWidget {
  final String label;
  final bool current;
  const _RailEntry({
    required this.label,
    this.current = false,
  });

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

// -----------------------------------------------------------------------------
// Main markdown pane (stub — Text + style composition, no real md lib)
// -----------------------------------------------------------------------------

class _MarkdownPane extends StatelessWidget {
  const _MarkdownPane();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return ColoredBox(
      color: t.surfaceBackground,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _MdH1('Auth flow — TOTP rollout'),
                  const _MdPara(
                    'Add TOTP as a second factor for the internal admin '
                    'dashboard. Rollout in two stages: opt-in beta, then '
                    'required after 30 days.',
                  ),
                  const _MdH2('Goals'),
                  const _MdBullets([
                    _BulletItem(
                      'G1. Reduce account takeover risk from password reuse.',
                    ),
                    _BulletItem(
                      'G2. Keep login frictionless for existing sessions.',
                    ),
                    _BulletItem(
                      'G3. Support recovery without a second device.',
                    ),
                  ]),
                  const _MdH2('Non-goals'),
                  const _MdBullets([
                    _BulletItem(
                      'Hardware keys (FIDO2) in this phase.',
                      strikethrough: true,
                    ),
                    _BulletItem('External customer auth — out of scope.'),
                  ]),
                  const _MdH2('Open questions'),
                  const _MdNumberedList([
                    'Q1. Should the flow support magic-link fallback?',
                    'Q2. Refresh-token lifetime when TOTP is active?',
                    'Q3. Recovery code rotation policy?',
                    'Q4. Do we block legacy sessions on rollout day?',
                  ]),
                  const _MdH2('Implementation sketch'),
                  const _MdCodeBlock(
                    'POST /api/auth/totp/enroll\n'
                    'GET  /api/auth/totp/challenge\n'
                    'POST /api/auth/totp/verify',
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MdH1 extends StatelessWidget {
  final String text;
  const _MdH1(this.text);

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Text(
        text,
        style: TextStyle(
          color: t.textPrimary,
          fontSize: 28,
          fontWeight: FontWeight.w700,
          height: 1.25,
          letterSpacing: -0.4,
        ),
      ),
    );
  }
}

class _MdH2 extends StatelessWidget {
  final String text;
  const _MdH2(this.text);

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 10),
      child: Text(
        text,
        style: TextStyle(
          color: t.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w600,
          height: 1.3,
          letterSpacing: -0.2,
        ),
      ),
    );
  }
}

class _MdPara extends StatelessWidget {
  final String text;
  const _MdPara(this.text);

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: TextStyle(
          color: t.textPrimary,
          fontSize: 14,
          height: 1.6,
        ),
      ),
    );
  }
}

class _BulletItem {
  final String text;
  final bool strikethrough;
  const _BulletItem(this.text, {this.strikethrough = false});
}

class _MdBullets extends StatelessWidget {
  final List<_BulletItem> items;
  const _MdBullets(this.items);

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 4, left: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 8, right: 10),
                  child: Container(
                    width: 4,
                    height: 4,
                    decoration: BoxDecoration(
                      color: t.textMuted,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    item.text,
                    style: TextStyle(
                      color: item.strikethrough ? t.textMuted : t.textPrimary,
                      fontSize: 14,
                      height: 1.55,
                      decoration: item.strikethrough
                          ? TextDecoration.lineThrough
                          : TextDecoration.none,
                      decorationColor: t.textMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _MdNumberedList extends StatelessWidget {
  final List<String> items;
  const _MdNumberedList(this.items);

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < items.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 4, left: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 24,
                  child: Text(
                    '${i + 1}.',
                    style: TextStyle(
                      color: t.textMuted,
                      fontSize: 14,
                      height: 1.55,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    items[i],
                    style: TextStyle(
                      color: t.textPrimary,
                      fontSize: 14,
                      height: 1.55,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _MdCodeBlock extends StatelessWidget {
  final String code;
  const _MdCodeBlock(this.code);

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: t.surfaceSunken,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: t.borderSubtle),
      ),
      child: Text(
        code,
        style: appMono(
          context,
          size: 12.5,
          color: t.textPrimary,
        ).copyWith(height: 1.55),
      ),
    );
  }
}
