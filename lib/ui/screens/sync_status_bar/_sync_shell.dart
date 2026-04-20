import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';

/// Direction the sync is running in. Controls which action button is shown as
/// "active" (faded primary) in the top chrome.
enum SyncDirection { down, up }

/// Shared visual shell for the Sync Down / Sync Up in-progress screens.
///
/// Pure UI stub for the mockup browser — no real sync work happens here.
/// Renders the top chrome (repo/branch chip + the two action buttons, both
/// disabled while syncing), the centered spinner + headings, the log box,
/// and the bottom helper caption.
class SyncShell extends StatelessWidget {
  final SyncDirection direction;
  final String heading;
  final String subheading;
  final List<SyncLogLine> logLines;
  final double logBoxWidth;
  final String caption;

  const SyncShell({
    super.key,
    required this.direction,
    required this.heading,
    required this.subheading,
    required this.logLines,
    required this.caption,
    this.logBoxWidth = 460,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return ColoredBox(
      color: t.surfaceBackground,
      child: Column(
        children: [
          _SyncChrome(direction: direction),
          Container(height: 1, color: t.borderSubtle),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: Column(
                children: [
                  Expanded(
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 80,
                            height: 80,
                            child: CircularProgressIndicator(
                              strokeWidth: 4,
                              color: t.accentPrimary,
                              backgroundColor: t.borderSubtle,
                            ),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            heading,
                            style: TextStyle(
                              color: t.textPrimary,
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.2,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            subheading,
                            style: TextStyle(
                              color: t.textMuted,
                              fontSize: 13,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 20),
                          _LogBox(width: logBoxWidth, lines: logLines),
                        ],
                      ),
                    ),
                  ),
                  Text(
                    caption,
                    style: TextStyle(
                      color: t.textMuted,
                      fontSize: 11,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Top chrome strip: repo name + branch chip (left) and the two sync buttons
/// (right). Both buttons are rendered disabled/faded while a sync is in
/// progress. The button that matches [direction] takes the "primary" slot.
class _SyncChrome extends StatelessWidget {
  final SyncDirection direction;
  const _SyncChrome({required this.direction});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final isDown = direction == SyncDirection.down;
    return Container(
      color: t.surfaceElevated,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          Text(
            'payments-api',
            style: TextStyle(
              color: t.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 10),
          _BranchChip(label: 'claude-jobs'),
          const Spacer(),
          if (isDown) ...[
            _GhostButton(
              icon: Icons.arrow_upward_rounded,
              label: 'Sync Up',
            ),
            const SizedBox(width: 8),
            _PrimaryButton(
              icon: Icons.arrow_downward_rounded,
              label: 'Syncing down…',
            ),
          ] else ...[
            _GhostButton(
              icon: Icons.arrow_downward_rounded,
              label: 'Sync Down',
            ),
            const SizedBox(width: 8),
            _PrimaryButton(
              icon: Icons.arrow_upward_rounded,
              label: 'Syncing up…',
            ),
          ],
        ],
      ),
    );
  }
}

class _BranchChip extends StatelessWidget {
  final String label;
  const _BranchChip({required this.label});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: t.surfaceSunken,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: t.borderSubtle),
      ),
      child: Text(
        label,
        style: appMono(context, size: 11, color: t.textMuted),
      ),
    );
  }
}

class _GhostButton extends StatelessWidget {
  final IconData icon;
  final String label;
  const _GhostButton({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Opacity(
      opacity: 0.5,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: t.surfaceElevated,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: t.borderSubtle),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: t.textPrimary),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: t.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final IconData icon;
  final String label;
  const _PrimaryButton({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Opacity(
      opacity: 0.6,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: t.accentPrimary,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: Colors.white),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Status marker preceding a log line. Determines the glyph + color.
enum SyncLogStatus { success, active, pending }

class SyncLogLine {
  final SyncLogStatus status;
  final String text;
  const SyncLogLine({required this.status, required this.text});
}

class _LogBox extends StatelessWidget {
  final double width;
  final List<SyncLogLine> lines;
  const _LogBox({required this.width, required this.lines});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      width: width,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.surfaceSunken,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: t.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < lines.length; i++) ...[
            if (i > 0) const SizedBox(height: 4),
            _LogLine(line: lines[i]),
          ],
        ],
      ),
    );
  }
}

class _LogLine extends StatelessWidget {
  final SyncLogLine line;
  const _LogLine({required this.line});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final (glyph, color) = switch (line.status) {
      SyncLogStatus.success => ('✓', t.statusSuccess),
      SyncLogStatus.active => ('→', t.textMuted),
      SyncLogStatus.pending => ('⋯', t.textMuted),
    };
    // Monospace used for alignment; the body text stays at textPrimary while
    // the leading glyph is colored by status.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 14,
          child: Text(
            glyph,
            style: appMono(context, size: 12, color: color, weight: FontWeight.w600),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            line.text,
            style: appMono(
              context,
              size: 12,
              color: line.status == SyncLogStatus.pending ? t.textMuted : t.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}
