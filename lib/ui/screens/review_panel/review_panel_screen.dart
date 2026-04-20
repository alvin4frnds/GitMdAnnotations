import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';

/// Review panel — Screen 6 of the mockup spike.
///
/// Split-pane layout: left 1fr annotated markdown (with faint ink-stroke
/// hints at three anchor points), right 420px typed review panel on a
/// slightly sunken surface. Top chrome mirrors the shell style: mono
/// breadcrumb left, auto-save caption mid-right, primary submit button
/// far right.
///
/// Spike-only: typed answers are inline stubs (Q1 / Q2 filled, Q3 / Q4
/// empty with italic-muted placeholders). [TextField]s are used with
/// [InputBorder.none] + a bottom-only focus underline; no controllers —
/// nothing leaks beyond this screen.
class ReviewPanelScreen extends StatelessWidget {
  const ReviewPanelScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return ColoredBox(
      color: t.surfaceBackground,
      child: Column(
        children: [
          const _ChromeBar(),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: const [
                Expanded(child: _MarkdownPane()),
                SizedBox(
                  width: 420,
                  child: _ReviewPanel(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Top chrome
// ---------------------------------------------------------------------------

class _ChromeBar extends StatelessWidget {
  const _ChromeBar();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: t.surfaceElevated,
        border: Border(bottom: BorderSide(color: t.borderSubtle)),
      ),
      child: Row(
        children: [
          Text(
            '03-review.md — draft',
            style: appMono(
              context,
              size: 13,
              weight: FontWeight.w500,
              color: t.textPrimary,
            ),
          ),
          const SizedBox(width: 16),
          Text(
            'auto-saved 3s ago',
            style: TextStyle(color: t.textMuted, fontSize: 12),
          ),
          const Spacer(),
          ElevatedButton(
            onPressed: () {},
            child: const Text('Submit review'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Left pane — annotated markdown stub
// ---------------------------------------------------------------------------

class _MarkdownPane extends StatelessWidget {
  const _MarkdownPane();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      color: t.surfaceElevated,
      child: Stack(
        children: [
          // Rendered-markdown stub
          SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(40, 28, 40, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Auth flow — TOTP rollout',
                  style: TextStyle(
                    color: t.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 18),
                _mdH2(context, 'Goals'),
                const SizedBox(height: 6),
                _mdP(
                  context,
                  'Ship time-based one-time passcodes as the primary second '
                  'factor for all tier-1 accounts, replacing SMS fallback.',
                ),
                const SizedBox(height: 14),
                _mdH2(context, 'Assumptions'),
                const SizedBox(height: 6),
                _mdP(
                  context,
                  'Users already have the companion mobile app installed and '
                  'signed in. Recovery codes are issued once, at enrollment.',
                ),
                const SizedBox(height: 14),
                _mdH2(context, 'Open questions'),
                const SizedBox(height: 6),
                _mdP(
                  context,
                  'Q1 — Magic-link fallback? Q2 — Grace period length? Q3 — '
                  'Session store: Redis vs config? Q4 — Rate-limit scope?',
                ),
                const SizedBox(height: 14),
                _mdH2(context, 'Implementation sketch'),
                const SizedBox(height: 6),
                _mdP(
                  context,
                  'TOTP secret generated server-side, displayed as QR once. '
                  'Verification endpoint validates RFC 6238 windows of ±1.',
                ),
                const SizedBox(height: 24),
                Text(
                  '3 stroke groups · 2 margin notes',
                  style: TextStyle(color: t.textMuted, fontSize: 11),
                ),
              ],
            ),
          ),
          // Faint ink-stroke overlay hints at anchor points.
          Positioned(
            left: 60,
            top: 150,
            child: _StrokeHint(color: t.inkRed),
          ),
          Positioned(
            left: 120,
            top: 250,
            child: _StrokeHint(color: t.inkBlue),
          ),
          Positioned(
            left: 80,
            top: 430,
            child: _StrokeHint(color: t.inkGreen),
          ),
        ],
      ),
    );
  }

  Widget _mdH2(BuildContext context, String text) => Text(
    text,
    style: TextStyle(
      color: context.tokens.textPrimary,
      fontSize: 15,
      fontWeight: FontWeight.w700,
    ),
  );

  Widget _mdP(BuildContext context, String text) => Text(
    text,
    style: TextStyle(
      color: context.tokens.textPrimary,
      fontSize: 12,
      height: 1.55,
    ),
  );
}

class _StrokeHint extends StatelessWidget {
  final Color color;
  const _StrokeHint({required this.color});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: color.withValues(alpha: 0.35),
            width: 2,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Right pane — typed review panel (420 px)
// ---------------------------------------------------------------------------

class _ReviewPanel extends StatelessWidget {
  const _ReviewPanel();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      decoration: BoxDecoration(
        color: t.surfaceSunken,
        border: Border(left: BorderSide(color: t.borderSubtle)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header row: file name + timestamp
            Row(
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
                  '2026-04-20 09:32 local',
                  style: appMono(context, size: 11, color: t.textMuted),
                ),
              ],
            ),
            const SizedBox(height: 18),

            _SectionHeader('Answers to open questions'),
            const SizedBox(height: 10),
            const _QuestionCard(
              title: 'Q1: Should the flow support magic-link fallback?',
              stubAnswer:
                  'TOTP first; magic-links only as fallback for recovery. '
                  'Document explicitly.',
            ),
            const SizedBox(height: 12),
            const _QuestionCard(
              title: 'Q2: Session-cookie grace period — 7 or 14 days?',
              stubAnswer: '14 — match the refresh-token lifetime.',
            ),
            const SizedBox(height: 12),
            const _QuestionCard(
              title: 'Q3: Session store — Redis, or read from config?',
              stubAnswer: null,
            ),
            const SizedBox(height: 12),
            const _QuestionCard(
              title: 'Q4: Rate-limit TOTP attempts per account or per IP?',
              stubAnswer: null,
            ),

            const SizedBox(height: 22),
            _SectionHeader('Free-form notes'),
            const SizedBox(height: 10),
            const _FreeFormNotes(
              stub:
                  'Assumptions section needs numbering (per stroke group B). '
                  'Flagged line 23 — recovery codes should rotate on use.',
            ),

            const SizedBox(height: 22),
            _SectionHeader('Spatial references'),
            const SizedBox(height: 10),
            _SpatialRefs(
              refs: [
                _SpatialRef(
                  color: t.inkRed,
                  text: 'Group A -> line 47 (near H2: Goals)',
                ),
                _SpatialRef(
                  color: t.inkBlue,
                  text: 'Group B -> line 23 (near "Assumptions")',
                ),
                _SpatialRef(
                  color: t.inkGreen,
                  text: 'Group C -> line 89 (near "Implementation sketch")',
                ),
              ],
            ),
          ],
        ),
      ),
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

// ---------------------------------------------------------------------------
// Question card with TextField-like input surface.
// ---------------------------------------------------------------------------

class _QuestionCard extends StatelessWidget {
  final String title;
  final String? stubAnswer;
  const _QuestionCard({required this.title, required this.stubAnswer});

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
            title,
            style: TextStyle(
              color: t.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 6),
          _AnswerField(stub: stubAnswer),
        ],
      ),
    );
  }
}

/// Borderless, multi-line input that shows either the stub answer (as real
/// prefilled text via `initialValue`) or an italic muted placeholder. On
/// focus a soft bottom underline appears. Uses `TextFormField` so no
/// controller leaks beyond this screen.
class _AnswerField extends StatelessWidget {
  final String? stub;
  const _AnswerField({required this.stub});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return TextFormField(
      initialValue: stub,
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
        hintText: stub == null ? 'Your answer...' : null,
        hintStyle: TextStyle(
          color: t.textMuted,
          fontSize: 13,
          height: 1.4,
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Free-form notes input
// ---------------------------------------------------------------------------

class _FreeFormNotes extends StatelessWidget {
  final String stub;
  const _FreeFormNotes({required this.stub});

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
      child: TextFormField(
        initialValue: stub,
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
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Spatial references list
// ---------------------------------------------------------------------------

class _SpatialRef {
  final Color color;
  final String text;
  const _SpatialRef({required this.color, required this.text});
}

class _SpatialRefs extends StatelessWidget {
  final List<_SpatialRef> refs;
  const _SpatialRefs({required this.refs});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final r in refs)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  margin: const EdgeInsets.only(right: 10),
                  decoration: BoxDecoration(
                    color: r.color,
                    shape: BoxShape.circle,
                  ),
                ),
                Expanded(
                  child: Text(
                    r.text,
                    style: appMono(
                      context,
                      size: 11,
                      color: t.textPrimary,
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
