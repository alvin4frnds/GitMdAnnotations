import 'package:flutter/material.dart';

import '../../../domain/entities/anchor.dart';
import '../../../domain/entities/job_ref.dart';
import '../../../domain/entities/source_kind.dart';
import '../../../domain/entities/spec_file.dart';
import '../../../domain/entities/stroke_group.dart';
import '../_shared/file_list_row.dart';

/// Static preview of the files the review-submit commit will produce.
/// T7 renders a deterministic list from the caller-supplied inputs —
/// full planned-writes introspection is deferred because `CommitPlanner`
/// does real invariant checking that the UI shouldn't re-run for a
/// preview (the preview is just a hint; the actual commit uses the
/// planner).
class PlannedWritesPreview extends StatelessWidget {
  const PlannedWritesPreview({
    required this.jobRef,
    required this.source,
    required this.strokeGroups,
    super.key,
  });

  final JobRef jobRef;
  final SpecFile source;
  final List<StrokeGroup> strokeGroups;

  @override
  Widget build(BuildContext context) {
    final rows = _buildRows();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < rows.length; i++)
          FileListRow(
            prefix: rows[i].prefix,
            name: rows[i].name,
            meta: rows[i].meta,
            first: i == 0,
          ),
      ],
    );
  }

  List<_Row> _buildRows() {
    final isMd = source.sourceKind == SourceKind.markdown;
    final rows = <_Row>[
      const _Row('+', '03-review.md', 'will be written'),
    ];
    if (isMd) {
      rows.add(_Row('+', '03-annotations.svg', '${strokeGroups.length} groups'));
      rows.add(const _Row('+', '03-annotations.png', 'flattened'));
      rows.add(_Row('~', _basename(source.path), 'changelog +1 line'));
    } else {
      final pages = <int>{};
      for (final g in strokeGroups) {
        final a = g.anchor;
        if (a is PdfAnchor) pages.add(a.page);
      }
      for (final p in pages.toList()..sort()) {
        rows.add(_Row('+', '03-annotations-p$p.svg', '1 page'));
        rows.add(_Row('+', '03-annotations-p$p.png', 'flattened'));
      }
      rows.add(const _Row('~', 'CHANGELOG.md', 'changelog +1 line'));
    }
    return rows;
  }

  static String _basename(String path) {
    final slash = path.lastIndexOf(RegExp(r'[/\\]'));
    return slash < 0 ? path : path.substring(slash + 1);
  }
}

class _Row {
  const _Row(this.prefix, this.name, this.meta);
  final String prefix;
  final String name;
  final String meta;
}
