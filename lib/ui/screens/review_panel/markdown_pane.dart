import 'package:flutter/material.dart';

import '../../theme/tokens.dart';
import 'stroke_hint.dart';

/// Left pane of the review screen — a stub markdown render with three
/// faint ink-stroke hints overlaid at rough anchor positions. The stubs
/// are intentional for the M1a spike; real markdown rendering lands with
/// the MarkdownRenderer wiring milestone.
class MarkdownPane extends StatelessWidget {
  const MarkdownPane({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      color: t.surfaceElevated,
      child: Stack(
        children: [
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
                _H2(context, 'Goals'),
                const SizedBox(height: 6),
                _P(
                  context,
                  'Ship time-based one-time passcodes as the primary second '
                  'factor for all tier-1 accounts, replacing SMS fallback.',
                ),
                const SizedBox(height: 14),
                _H2(context, 'Assumptions'),
                const SizedBox(height: 6),
                _P(
                  context,
                  'Users already have the companion mobile app installed and '
                  'signed in. Recovery codes are issued once, at enrollment.',
                ),
                const SizedBox(height: 14),
                _H2(context, 'Open questions'),
                const SizedBox(height: 6),
                _P(
                  context,
                  'Q1 — Magic-link fallback? Q2 — Grace period length? Q3 — '
                  'Session store: Redis vs config? Q4 — Rate-limit scope?',
                ),
                const SizedBox(height: 14),
                _H2(context, 'Implementation sketch'),
                const SizedBox(height: 6),
                _P(
                  context,
                  'TOTP secret generated server-side, displayed as QR once. '
                  'Verification endpoint validates RFC 6238 windows of +/-1.',
                ),
                const SizedBox(height: 24),
                Text(
                  '3 stroke groups, 2 margin notes',
                  style: TextStyle(color: t.textMuted, fontSize: 11),
                ),
              ],
            ),
          ),
          Positioned(
            left: 60,
            top: 150,
            child: StrokeHint(color: t.inkRed, variant: 1),
          ),
          Positioned(
            left: 120,
            top: 250,
            child: StrokeHint(color: t.inkBlue, variant: 2),
          ),
          Positioned(
            left: 80,
            top: 430,
            child: StrokeHint(color: t.inkGreen, variant: 3),
          ),
        ],
      ),
    );
  }

  // ignore: non_constant_identifier_names
  Widget _H2(BuildContext context, String text) => Text(
        text,
        style: TextStyle(
          color: context.tokens.textPrimary,
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
      );

  // ignore: non_constant_identifier_names
  Widget _P(BuildContext context, String text) => Text(
        text,
        style: TextStyle(
          color: context.tokens.textPrimary,
          fontSize: 12,
          height: 1.55,
        ),
      );
}
