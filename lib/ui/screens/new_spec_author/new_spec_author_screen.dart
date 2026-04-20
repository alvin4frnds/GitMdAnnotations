import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';

/// New-spec authoring screen (Phase 2, UI spike).
///
/// Visual-only: no real markdown editor, no linter, no commit wiring. The
/// rendered markdown pane is a stub composed of [Text] widgets styled to look
/// like a live editor. The `Commit to claude-jobs` button shows a disabled
/// look because the stub linter flags `File-level change plan` as missing.
class NewSpecAuthorScreen extends StatelessWidget {
  const NewSpecAuthorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return ColoredBox(
      color: t.surfaceBackground,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: const [
          _TopChrome(),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Sidebar(),
                Expanded(child: _EditorPane()),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Top chrome (52px): breadcrumb + Save draft + disabled Commit
// -----------------------------------------------------------------------------

class _TopChrome extends StatelessWidget {
  const _TopChrome();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: t.surfaceElevated,
        border: Border(bottom: BorderSide(color: t.borderSubtle)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'jobs/pending/spec-api-rate-limit/02-spec.md',
              style: appMono(
                context,
                size: 13,
                weight: FontWeight.w500,
                color: t.textPrimary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 12),
          const _GhostButton(label: 'Save draft'),
          const SizedBox(width: 8),
          const _CommitDisabledButton(label: 'Commit to claude-jobs'),
        ],
      ),
    );
  }
}

class _GhostButton extends StatelessWidget {
  final String label;
  const _GhostButton({required this.label});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return TextButton(
      onPressed: () {},
      style: TextButton.styleFrom(
        foregroundColor: t.textPrimary,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: t.borderSubtle),
        ),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
      ),
    );
  }
}

/// Primary button in a visually-disabled state — grey fill + muted text.
/// `onPressed: null` gives Flutter's built-in disabled cursor on web and is
/// the canonical way to signal "not interactive" on other platforms.
class _CommitDisabledButton extends StatelessWidget {
  final String label;
  const _CommitDisabledButton({required this.label});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return MouseRegion(
      cursor: SystemMouseCursors.basic,
      child: ElevatedButton(
        onPressed: null,
        style: ElevatedButton.styleFrom(
          backgroundColor: t.accentPrimary.withValues(alpha: 0.35),
          foregroundColor: Colors.white.withValues(alpha: 0.8),
          disabledBackgroundColor: t.surfaceSunken,
          disabledForegroundColor: t.textMuted,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: t.borderSubtle),
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Left sidebar (224px): template picker + required-sections checklist + error
// -----------------------------------------------------------------------------

class _Sidebar extends StatelessWidget {
  const _Sidebar();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      width: 224,
      decoration: BoxDecoration(
        color: t.surfaceElevated,
        border: Border(right: BorderSide(color: t.borderSubtle)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(12, 18, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _SidebarSectionLabel('TEMPLATE'),
                  const SizedBox(height: 8),
                  const _TemplateRow(
                    icon: Icons.api_outlined,
                    label: 'API change',
                    selected: true,
                  ),
                  const _TemplateRow(
                    icon: Icons.design_services_outlined,
                    label: 'UI/UX mockup',
                  ),
                  const _TemplateRow(
                    icon: Icons.swap_horiz_outlined,
                    label: 'Data migration',
                  ),
                  const _TemplateRow(
                    icon: Icons.description_outlined,
                    label: 'RFC / design doc',
                  ),
                  const SizedBox(height: 16),
                  Container(height: 1, color: t.borderSubtle),
                  const SizedBox(height: 16),
                  const _SidebarSectionLabel('REQUIRED SECTIONS'),
                  const SizedBox(height: 10),
                  _RequiredRow(
                    icon: Icons.check_circle,
                    color: t.statusSuccess,
                    label: 'Goals',
                  ),
                  _RequiredRow(
                    icon: Icons.check_circle,
                    color: t.statusSuccess,
                    label: 'Non-goals',
                  ),
                  _RequiredRow(
                    icon: Icons.error_outline,
                    color: t.statusWarning,
                    label: 'Open questions',
                    hint: 'add at least 1',
                  ),
                  _RequiredRow(
                    icon: Icons.cancel_outlined,
                    color: t.statusDanger,
                    label: 'File-level change plan',
                    hint: 'required',
                  ),
                ],
              ),
            ),
          ),
          const _LinterErrorCard(),
        ],
      ),
    );
  }
}

class _SidebarSectionLabel extends StatelessWidget {
  final String text;
  const _SidebarSectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        text,
        style: TextStyle(
          color: t.textMuted,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _TemplateRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  const _TemplateRow({
    required this.icon,
    required this.label,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final fg = selected ? t.accentPrimary : t.textPrimary;
    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      decoration: BoxDecoration(
        color: selected ? t.accentSoftBg : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 16,
            color: selected ? t.accentPrimary : t.textMuted,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: fg,
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                height: 1.3,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _RequiredRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String? hint;
  const _RequiredRow({
    required this.icon,
    required this.color,
    required this.label,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 3, 4, 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 14, color: color),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: t.textPrimary,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
                if (hint != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Text(
                      hint!,
                      style: TextStyle(
                        color: color,
                        fontSize: 11,
                        height: 1.3,
                      ),
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

class _LinterErrorCard extends StatelessWidget {
  const _LinterErrorCard();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      decoration: BoxDecoration(
        color: t.statusDanger.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: t.statusDanger.withValues(alpha: 0.25),
        ),
      ),
      child: Text(
        'Commit blocked — File-level change plan is required.',
        style: TextStyle(
          color: t.statusDanger,
          fontSize: 11,
          height: 1.4,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Main editor pane — stub markdown rendering, padding 24
// -----------------------------------------------------------------------------

class _EditorPane extends StatelessWidget {
  const _EditorPane();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return ColoredBox(
      color: t.surfaceElevated,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: const [
            _MdH1('API rate-limit tuning'),
            _MdH2('Goals'),
            _MdBullets([
              'Lower the per-token ceiling from 120 rpm to 90 rpm during peak.',
              'Burst allowance of 2x for 10 s before throttling kicks in.',
            ]),
            _MdH2('Non-goals'),
            _MdBullets([
              'Changing auth flow or token format.',
              'Touching the v1 rate limiter (deprecated).',
            ]),
            _MdH2('Open questions'),
            _MdBullets([
              'Where should the burst counter live — Redis or in-process?',
            ]),
            _MissingH2('File-level change plan'),
            _MissingPlaceholder('required — please fill in'),
            SizedBox(height: 40),
          ],
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
      padding: const EdgeInsets.only(bottom: 14),
      child: Text(
        text,
        style: TextStyle(
          color: t.textPrimary,
          fontSize: 26,
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
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Text(
        text,
        style: TextStyle(
          color: t.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          height: 1.3,
          letterSpacing: -0.2,
        ),
      ),
    );
  }
}

class _MdBullets extends StatelessWidget {
  final List<String> items;
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
                    item,
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

/// H2 rendered in low-opacity statusDanger to signal a missing required section,
/// with a small red dot beside the heading.
class _MissingH2 extends StatelessWidget {
  final String text;
  const _MissingH2(this.text);

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final danger = t.statusDanger;
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Flexible(
            child: Text(
              text,
              style: TextStyle(
                color: danger.withValues(alpha: 0.55),
                fontSize: 18,
                fontWeight: FontWeight.w600,
                height: 1.3,
                letterSpacing: -0.2,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: danger,
              shape: BoxShape.circle,
            ),
          ),
        ],
      ),
    );
  }
}

class _MissingPlaceholder extends StatelessWidget {
  final String text;
  const _MissingPlaceholder(this.text);

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(top: 2, left: 4),
      child: Text(
        text,
        style: TextStyle(
          color: t.statusDanger.withValues(alpha: 0.6),
          fontSize: 14,
          height: 1.55,
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }
}
