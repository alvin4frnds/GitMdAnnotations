import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';

/// Screen 3 — Job list / pending specs (UI spike, stubbed).
class JobListScreen extends StatelessWidget {
  const JobListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return ColoredBox(
      color: t.surfaceBackground,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: const [
          _LeftRail(),
          Expanded(child: _MainArea()),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Left rail
// ---------------------------------------------------------------------------

class _LeftRail extends StatelessWidget {
  const _LeftRail();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      width: 208,
      decoration: BoxDecoration(
        color: t.surfaceElevated,
        border: Border(right: BorderSide(color: t.borderSubtle)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SectionHeader(label: 'Phase'),
          const SizedBox(height: 8),
          const _FilterRow(label: 'All', count: '3', selected: true),
          const SizedBox(height: 2),
          const _FilterRow(label: 'Awaiting review', count: '2'),
          const SizedBox(height: 2),
          const _FilterRow(label: 'Awaiting revision', count: '1'),
          const SizedBox(height: 2),
          const _FilterRow(label: 'Approved', count: '0'),
          const SizedBox(height: 16),
          Divider(height: 1, color: t.borderSubtle),
          const SizedBox(height: 16),
          _NewSpecButton(onPressed: () {}),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          color: t.textMuted,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _FilterRow extends StatelessWidget {
  final String label;
  final String count;
  final bool selected;
  const _FilterRow({required this.label, required this.count, this.selected = false});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final bg = selected ? t.accentSoftBg : Colors.transparent;
    final fg = selected ? t.accentPrimary : t.textPrimary;
    final countFg = selected ? t.accentPrimary : t.textMuted;

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () {},
        hoverColor: selected ? t.accentSoftBg : t.surfaceSunken,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: fg,
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                count,
                style: TextStyle(color: countFg, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NewSpecButton extends StatelessWidget {
  final VoidCallback onPressed;
  const _NewSpecButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: t.accentPrimary,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.add_rounded, size: 16, color: Colors.white),
            SizedBox(width: 6),
            Text(
              'New spec',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Main area
// ---------------------------------------------------------------------------

class _MainArea extends StatelessWidget {
  const _MainArea();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: const [
        _TopChrome(),
        Expanded(child: _JobList()),
      ],
    );
  }
}

class _TopChrome extends StatelessWidget {
  const _TopChrome();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: t.surfaceElevated,
        border: Border(bottom: BorderSide(color: t.borderSubtle)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Text(
            'payments-api',
            style: appMono(context, size: 12, weight: FontWeight.w600),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              '·',
              style: appMono(context, size: 12, color: t.textMuted),
            ),
          ),
          Text(
            'claude-jobs',
            style: appMono(context, size: 12, color: t.textMuted),
          ),
          const SizedBox(width: 16),
          Text(
            '3 jobs',
            style: TextStyle(color: t.textMuted, fontSize: 12),
          ),
          const Spacer(),
          _GhostButton(
            icon: Icons.arrow_downward_rounded,
            label: 'Sync Down',
            onPressed: () {},
          ),
          const SizedBox(width: 8),
          _SyncUpButton(onPressed: () {}, badgeCount: '1'),
        ],
      ),
    );
  }
}

class _GhostButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  const _GhostButton({required this.icon, required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: t.textPrimary,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: BorderSide(color: t.borderSubtle),
        ),
        minimumSize: const Size(0, 32),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: t.textPrimary),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

class _SyncUpButton extends StatelessWidget {
  final VoidCallback onPressed;
  final String badgeCount;
  const _SyncUpButton({required this.onPressed, required this.badgeCount});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: t.accentPrimary,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        minimumSize: const Size(0, 32),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.arrow_upward_rounded, size: 14, color: Colors.white),
          const SizedBox(width: 6),
          const Text(
            'Sync Up',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: t.statusWarning.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              badgeCount,
              style: TextStyle(
                color: t.statusWarning,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Job list
// ---------------------------------------------------------------------------

/// Internal stub data model — no logic, just shape for the layout.
class _JobStub {
  final String id;
  final _Phase phase;
  final _FileKind fileKind;
  final String preview;
  final String timestamp;
  final bool justArrived;

  const _JobStub({
    required this.id,
    required this.phase,
    required this.fileKind,
    required this.preview,
    required this.timestamp,
    this.justArrived = false,
  });
}

enum _Phase { awaitingReview, awaitingRevision }

enum _FileKind { md, pdf }

const List<_JobStub> _stubJobs = [
  _JobStub(
    id: 'spec-auth-flow-totp',
    phase: _Phase.awaitingReview,
    fileKind: _FileKind.md,
    preview:
        'TOTP rollout plan. Open questions on magic-link fallback and refresh-token lifetime.',
    timestamp: '2 min ago',
    justArrived: true,
  ),
  _JobStub(
    id: 'spec-invoice-pdf-redesign',
    phase: _Phase.awaitingReview,
    fileKind: _FileKind.pdf,
    preview:
        'Layout A vs B for the new PDF invoice template. Sample attached.',
    timestamp: '14 min ago',
  ),
  _JobStub(
    id: 'spec-webhook-retry-policy',
    phase: _Phase.awaitingRevision,
    fileKind: _FileKind.md,
    preview:
        'Revision v2 ready after review. Dead-letter behavior clarified.',
    timestamp: '1 h ago',
  ),
];

class _JobList extends StatelessWidget {
  const _JobList();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final rows = <Widget>[];
    for (var i = 0; i < _stubJobs.length; i++) {
      if (i > 0) {
        rows.add(Divider(height: 1, thickness: 1, color: t.borderSubtle));
      }
      rows.add(_JobRow(job: _stubJobs[i]));
    }
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: rows,
      ),
    );
  }
}

class _JobRow extends StatelessWidget {
  final _JobStub job;
  const _JobRow({required this.job});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final highlighted = job.justArrived;

    final bg = highlighted ? t.accentSoftBg : t.surfaceBackground;

    return Material(
      color: bg,
      child: InkWell(
        onTap: () {},
        hoverColor: highlighted ? t.accentSoftBg : t.surfaceSunken,
        child: Container(
          decoration: BoxDecoration(
            border: highlighted
                ? Border(left: BorderSide(color: t.accentPrimary, width: 4))
                : const Border(left: BorderSide(color: Colors.transparent, width: 4)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _PhaseTag(phase: job.phase),
                        const SizedBox(width: 8),
                        _FileKindChip(kind: job.fileKind),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Text(
                            job.id,
                            style: appMono(
                              context,
                              size: 13,
                              weight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (highlighted) ...[
                          const SizedBox(width: 10),
                          Text(
                            'just arrived',
                            style: TextStyle(
                              color: t.accentPrimary,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      job.preview,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: t.textMuted,
                        fontSize: 13,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      job.timestamp,
                      style: appMono(context, size: 11, color: t.textMuted),
                    ),
                    const SizedBox(width: 8),
                    Icon(Icons.chevron_right_rounded,
                        size: 18, color: t.textMuted),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PhaseTag extends StatelessWidget {
  final _Phase phase;
  const _PhaseTag({required this.phase});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    // Phase tag colors — derived from tokens:
    //   Awaiting review  → indigo (accentPrimary over accentSoftBg)
    //   Awaiting revision → amber (statusWarning soft bg + strong text)
    late final Color bg;
    late final Color fg;
    late final String label;
    switch (phase) {
      case _Phase.awaitingReview:
        bg = t.accentSoftBg;
        fg = t.accentPrimary;
        label = 'Awaiting review';
        break;
      case _Phase.awaitingRevision:
        bg = t.statusWarning.withValues(alpha: 0.15);
        fg = t.statusWarning;
        label = 'Awaiting revision';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: fg,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _FileKindChip extends StatelessWidget {
  final _FileKind kind;
  const _FileKindChip({required this.kind});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final label = kind == _FileKind.md ? '.md' : '.pdf';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: t.surfaceSunken,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: t.borderSubtle),
      ),
      child: Text(
        label,
        style: appMono(context, size: 10, color: t.textMuted),
      ),
    );
  }
}
