import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';

/// UI-spike mockup of the "Revision ready" changelog viewer (mockups.html
/// screen 9). Landscape tablet. Visual only — no controllers, no IO.
class ChangelogViewerScreen extends StatelessWidget {
  const ChangelogViewerScreen({super.key});

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
                _LeftNavRail(),
                Expanded(child: _MainContent()),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Top chrome (52px)
// ---------------------------------------------------------------------------

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
          // Breadcrumb
          Text(
            '04-spec-v2.md  \u00B7  spec-auth-flow-totp',
            style: appMono(context, size: 13, color: t.textPrimary),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: t.surfaceSunken,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: t.borderSubtle),
            ),
            child: Text(
              'v2',
              style: appMono(context, size: 10, color: t.textMuted),
            ),
          ),
          const Spacer(),
          _ReadyToApproveButton(),
        ],
      ),
    );
  }
}

class _ReadyToApproveButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Material(
      color: t.statusSuccess,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () {},
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_rounded, size: 16, color: Colors.white),
              const SizedBox(width: 6),
              const Text(
                'Ready to approve',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Left nav rail (192px)
// ---------------------------------------------------------------------------

class _LeftNavRail extends StatelessWidget {
  const _LeftNavRail();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      width: 192,
      decoration: BoxDecoration(
        color: t.surfaceElevated,
        border: Border(right: BorderSide(color: t.borderSubtle)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _RailSectionLabel(label: 'Versions'),
          const SizedBox(height: 8),
          _VersionItem(name: '02-spec.md'),
          _VersionItem(name: '03-review.md'),
          _VersionItem(name: '04-spec-v2.md', current: true),
          const SizedBox(height: 16),
          Divider(height: 1, color: t.borderSubtle),
          const SizedBox(height: 16),
          _RailSectionLabel(label: 'On this page'),
          const SizedBox(height: 8),
          _PageHeading(label: 'Goals'),
          _PageHeading(label: 'Open questions'),
          _PageHeading(label: 'Implementation sketch'),
          _PageHeading(label: 'Changelog', active: true),
        ],
      ),
    );
  }
}

class _RailSectionLabel extends StatelessWidget {
  final String label;
  const _RailSectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Text(
      label.toUpperCase(),
      style: TextStyle(
        color: t.textMuted,
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.6,
      ),
    );
  }
}

class _VersionItem extends StatelessWidget {
  final String name;
  final bool current;
  const _VersionItem({required this.name, this.current = false});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Text(
        name,
        style: appMono(
          context,
          size: 12,
          weight: current ? FontWeight.w700 : FontWeight.w400,
          color: current ? t.accentPrimary : t.textMuted,
        ),
      ),
    );
    if (!current) return content;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 1),
      decoration: BoxDecoration(
        color: t.accentSoftBg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: content,
    );
  }
}

class _PageHeading extends StatelessWidget {
  final String label;
  final bool active;
  const _PageHeading({required this.label, this.active = false});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Text(
        label,
        style: TextStyle(
          color: active ? t.accentPrimary : t.textMuted,
          fontSize: 12,
          fontWeight: active ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Main content (rendered markdown stub + changelog)
// ---------------------------------------------------------------------------

class _MainContent extends StatelessWidget {
  const _MainContent();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return ColoredBox(
      color: t.surfaceElevated,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(48, 32, 48, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _RenderedMarkdownStub(),
            const SizedBox(height: 32),
            _ChangelogSection(),
          ],
        ),
      ),
    );
  }
}

class _RenderedMarkdownStub extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Flexible(
              child: Text(
                'Auth flow \u2014 TOTP rollout',
                style: TextStyle(
                  color: t.textPrimary,
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.4,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(
                'v2',
                style: TextStyle(color: t.textMuted, fontSize: 13),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _Para(
          'This spec covers the rollout of TOTP as the primary second factor for '
          'the web app, with magic-link email as a fallback during the 14-day '
          'grace period.',
        ),
        const SizedBox(height: 10),
        _Para(
          'Desktop Claude drafted this from the original requirements; tablet '
          'feedback has been folded in as of 04-spec-v2.md.',
        ),
        const SizedBox(height: 24),
        _H2('Goals'),
        const SizedBox(height: 8),
        _Bullet('Enroll all active users in TOTP within 14 days of rollout.'),
        _Bullet('Keep magic-link fallback behind a feature flag.'),
        _Bullet('Preserve refresh-token lifetime for already-signed-in sessions.'),
        const SizedBox(height: 24),
        _H2('Implementation sketch'),
        const SizedBox(height: 8),
        _Para(
          'Session store becomes config-driven; existing Redis deployments '
          'migrate via a one-shot script run at deploy time. Lockout behavior '
          'for magic-link fallback is still open (see Q4).',
        ),
      ],
    );
  }
}

class _H2 extends StatelessWidget {
  final String text;
  const _H2(this.text);

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Text(
      text,
      style: TextStyle(
        color: t.textPrimary,
        fontSize: 18,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
      ),
    );
  }
}

class _Para extends StatelessWidget {
  final String text;
  const _Para(this.text);

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Text(
      text,
      style: TextStyle(
        color: t.textPrimary,
        fontSize: 14,
        height: 1.55,
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  final String text;
  const _Bullet(this.text);

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(left: 6, top: 3, bottom: 3),
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
              text,
              style: TextStyle(
                color: t.textPrimary,
                fontSize: 14,
                height: 1.55,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Changelog section
// ---------------------------------------------------------------------------

class _ChangelogSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _H2('Changelog'),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: t.surfaceSunken,
            border: Border.all(color: t.borderSubtle),
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              _ChangelogRow(
                timestamp: '2026-04-19 14:32',
                phase: _Phase.desktop,
                description: 'Initial spec authored by desktop Claude.',
              ),
              SizedBox(height: 10),
              _ChangelogRow(
                timestamp: '2026-04-20 10:02',
                phase: _Phase.tablet,
                description:
                    'Clarified TOTP rollout plan; added open questions on magic-link fallback.',
              ),
              SizedBox(height: 10),
              _ChangelogRow(
                timestamp: '2026-04-20 12:18',
                phase: _Phase.desktop,
                description:
                    'Revised spec to v2; incorporated tablet feedback on refresh-token lifetime.',
                highlighted: true,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

enum _Phase { desktop, tablet }

class _ChangelogRow extends StatelessWidget {
  final String timestamp;
  final _Phase phase;
  final String description;
  final bool highlighted;

  const _ChangelogRow({
    required this.timestamp,
    required this.phase,
    required this.description,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              timestamp,
              style: appMono(context, size: 11, color: t.textMuted),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: _PhaseTag(phase: phase),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            description,
            style: TextStyle(
              color: t.textPrimary,
              fontSize: 13,
              height: 1.5,
            ),
          ),
        ),
        if (highlighted) ...[
          const SizedBox(width: 10),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              'latest',
              style: TextStyle(
                color: t.accentPrimary,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.4,
              ),
            ),
          ),
        ],
      ],
    );

    if (!highlighted) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: row,
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: t.accentSoftBg,
        borderRadius: BorderRadius.circular(4),
        border: Border(
          left: BorderSide(color: t.accentPrimary, width: 4),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      child: row,
    );
  }
}

class _PhaseTag extends StatelessWidget {
  final _Phase phase;
  const _PhaseTag({required this.phase});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final isTablet = phase == _Phase.tablet;
    final bg = isTablet ? t.accentPrimary : t.textMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        isTablet ? 'tablet' : 'desktop',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}
