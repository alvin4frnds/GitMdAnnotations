import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/controllers/changelog_viewer_controller.dart';
import '../../../app/providers/spec_providers.dart';
import '../../../domain/entities/repo_ref.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import 'changelog_timeline.dart';

/// Screen 9 — Cross-job `## Changelog` timeline (IMPLEMENTATION.md §6.4
/// M1d-T1, PRD §5.9 FR-1.37).
///
/// Layout mirrors [JobListScreen]: left rail + main pane + loading /
/// error / empty states driven off an `AsyncValue<ChangelogViewerState>`.
/// Timeline rendering and row widgets live in [changelog_timeline.dart]
/// so this file stays under the §2.6 line-cap.
class ChangelogViewerScreen extends ConsumerWidget {
  const ChangelogViewerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final async = ref.watch(changelogViewerControllerProvider);
    final repo = ref.watch(currentRepoProvider);
    return ColoredBox(
      color: t.surfaceBackground,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _LeftRail(),
          Expanded(child: _MainArea(async: async, repo: repo)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Left rail — minimal: just back-to-jobs + section label.
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              'HISTORY',
              style: TextStyle(
                color: t.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(height: 8),
          _NavRow(
            icon: Icons.history_rounded,
            label: 'Changelog',
            selected: true,
          ),
          const SizedBox(height: 16),
          Divider(height: 1, color: t.borderSubtle),
          const SizedBox(height: 16),
          _NavRow(
            icon: Icons.arrow_back_rounded,
            label: 'Back to jobs',
            onTap: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
    );
  }
}

class _NavRow extends StatelessWidget {
  const _NavRow({
    required this.icon,
    required this.label,
    this.selected = false,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final bg = selected ? t.accentSoftBg : Colors.transparent;
    final fg = selected ? t.accentPrimary : t.textPrimary;
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        hoverColor: selected ? t.accentSoftBg : t.surfaceSunken,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          child: Row(
            children: [
              Icon(icon, size: 14, color: fg),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: fg,
                    fontSize: 13,
                    fontWeight:
                        selected ? FontWeight.w600 : FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
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
// Main area — top chrome + body.
// ---------------------------------------------------------------------------

class _MainArea extends StatelessWidget {
  const _MainArea({required this.async, required this.repo});
  final AsyncValue<ChangelogViewerState> async;
  final RepoRef? repo;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TopChrome(async: async, repo: repo),
        Expanded(child: _Body(async: async)),
      ],
    );
  }
}

class _TopChrome extends ConsumerWidget {
  const _TopChrome({required this.async, required this.repo});
  final AsyncValue<ChangelogViewerState> async;
  final RepoRef? repo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final state = async.value;
    final count =
        state is ChangelogViewerLoaded ? state.entries.length : 0;
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
            repo?.name ?? '—',
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
            'changelog',
            style: appMono(context, size: 12, color: t.textMuted),
          ),
          const SizedBox(width: 16),
          Text(
            '$count entries',
            style: TextStyle(color: t.textMuted, fontSize: 12),
          ),
          const Spacer(),
          IconButton(
            tooltip: 'Refresh',
            icon: Icon(Icons.refresh_rounded, size: 18, color: t.textPrimary),
            onPressed: () => ref
                .read(changelogViewerControllerProvider.notifier)
                .refresh(),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Body — switches on the AsyncValue<ChangelogViewerState>.
// ---------------------------------------------------------------------------

class _Body extends StatelessWidget {
  const _Body({required this.async});
  final AsyncValue<ChangelogViewerState> async;

  @override
  Widget build(BuildContext context) {
    if (async.isLoading && !async.hasValue) {
      return const _LoadingState();
    }
    if (async.hasError && !async.hasValue) {
      return _ErrorState(message: async.error.toString());
    }
    final state = async.value;
    if (state is ChangelogViewerEmpty) return const _EmptyState();
    if (state is ChangelogViewerLoaded) {
      if (state.entries.isEmpty) {
        return const _EmptyState(reason: 'No changelog entries yet');
      }
      return ChangelogTimeline(entries: state.entries);
    }
    return const _LoadingState();
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) =>
      const Center(child: CircularProgressIndicator());
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: t.statusDanger.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: t.statusDanger.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline_rounded,
                  size: 16, color: t.statusDanger),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  message,
                  style: TextStyle(
                    color: t.statusDanger,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({this.reason = 'No repo selected'});
  final String reason;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inbox_outlined, size: 32, color: t.textMuted),
          const SizedBox(height: 10),
          Text(
            reason,
            style: TextStyle(color: t.textMuted, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
