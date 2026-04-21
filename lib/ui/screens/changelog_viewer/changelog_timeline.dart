import 'package:flutter/material.dart';

import '../../../domain/entities/job_ref.dart';
import '../../../domain/services/changelog_aggregator.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';

/// Reverse-chronological timeline rendered from the aggregator output.
/// Entries are grouped under a single day-heading (one per calendar day)
/// and shown as rows of `time · job id · description · author` to match
/// the visual language of JobList (tokens + appMono for ids).
class ChangelogTimeline extends StatelessWidget {
  const ChangelogTimeline({super.key, required this.entries});

  /// Newest-first; the aggregator guarantees this order.
  final List<DatedChangelogEntry> entries;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final groups = _groupByDay(entries);
    final children = <Widget>[];
    for (var i = 0; i < groups.length; i++) {
      if (i > 0) children.add(const SizedBox(height: 24));
      children.add(_DayGroup(group: groups[i]));
    }
    return ColoredBox(
      color: t.surfaceBackground,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(32, 24, 32, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }
}

/// One calendar day + every entry that landed on it, order preserved
/// from the aggregator (newest first within the day).
class _DayGroupData {
  _DayGroupData(this.day, this.rows);
  final DateTime day;
  final List<DatedChangelogEntry> rows;
}

List<_DayGroupData> _groupByDay(List<DatedChangelogEntry> entries) {
  final groups = <_DayGroupData>[];
  DateTime? currentDay;
  List<DatedChangelogEntry>? currentRows;
  for (final e in entries) {
    final day = DateTime(
      e.entry.timestamp.year,
      e.entry.timestamp.month,
      e.entry.timestamp.day,
    );
    if (currentDay == null || day != currentDay) {
      currentRows = <DatedChangelogEntry>[];
      currentDay = day;
      groups.add(_DayGroupData(day, currentRows));
    }
    currentRows!.add(e);
  }
  return groups;
}

class _DayGroup extends StatelessWidget {
  const _DayGroup({required this.group});
  final _DayGroupData group;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            _formatDay(group.day),
            style: TextStyle(
              color: t.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: t.surfaceElevated,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: t.borderSubtle),
          ),
          child: Column(
            children: [
              for (var i = 0; i < group.rows.length; i++) ...[
                if (i > 0)
                  Divider(height: 1, thickness: 1, color: t.borderSubtle),
                _EntryRow(entry: group.rows[i]),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({required this.entry});
  final DatedChangelogEntry entry;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 56,
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                _formatTime(entry.entry.timestamp),
                style: appMono(context, size: 11, color: t.textMuted),
              ),
            ),
          ),
          const SizedBox(width: 10),
          _AuthorTag(author: entry.entry.author),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.entry.description,
                  style: TextStyle(
                    color: t.textPrimary,
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 4),
                _JobIdLabel(job: entry.job),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AuthorTag extends StatelessWidget {
  const _AuthorTag({required this.author});
  final String author;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    // `tablet` uses the accent colour (this-device-authored) so a glance
    // separates desktop-originating entries from on-device ones, same
    // palette split as the UI-spike mockup this file replaces.
    final isTablet = author.toLowerCase() == 'tablet';
    final bg = isTablet ? t.accentPrimary : t.textMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        author,
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

class _JobIdLabel extends StatelessWidget {
  const _JobIdLabel({required this.job});
  final JobRef job;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Text(
      job.jobId,
      style: appMono(context, size: 11, color: t.textMuted),
      overflow: TextOverflow.ellipsis,
    );
  }
}

// Public seam for widget tests that want to assert formatting without
// rebuilding the whole widget tree.
@visibleForTesting
String formatChangelogDay(DateTime day) => _formatDay(day);

@visibleForTesting
String formatChangelogTime(DateTime ts) => _formatTime(ts);

// ---------------------------------------------------------------------------
// Formatters — local time, no timezone suffix (matches [ChangelogEntry]
// contract documented in the entity).
// ---------------------------------------------------------------------------

const List<String> _monthNames = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _formatDay(DateTime d) =>
    '${_monthNames[d.month - 1].toUpperCase()} ${_two(d.day)}, ${d.year}';

String _formatTime(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}';

String _two(int v) => v.toString().padLeft(2, '0');
