import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/controllers/batch_spec_importer.dart';
import '../../../app/controllers/spec_importer.dart' show basename;
import '../../../app/providers/spec_import_providers.dart';
import '../../theme/tokens.dart';

/// Action bar shown above the entry list when ≥1 file is ticked and no
/// batch is running. Renders the running "N selected" count, a
/// "Select all"/"Clear" toggle scoped to the current directory's
/// convertible entries, and the primary "Convert N selected" button that
/// kicks off [BatchConvertController.run] (spec-005 §9).
class SelectionActionBar extends ConsumerWidget {
  const SelectionActionBar({
    super.key,
    required this.convertibleRelPaths,
    this.disabled = false,
  });

  /// Convertible entries currently listed — the scope of "Select all".
  final List<String> convertibleRelPaths;
  final bool disabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final selected = ref.watch(repoSelectionControllerProvider);
    final selection = ref.read(repoSelectionControllerProvider.notifier);
    final allHere = convertibleRelPaths.isNotEmpty &&
        convertibleRelPaths.every(selected.contains);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
      decoration: BoxDecoration(
        color: t.accentSoftBg,
        border: Border(bottom: BorderSide(color: t.borderSubtle)),
      ),
      child: Row(
        children: [
          Text(
            '${selected.length} selected',
            style: TextStyle(
              color: t.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          if (convertibleRelPaths.isNotEmpty)
            TextButton(
              onPressed: disabled
                  ? null
                  : () => allHere
                      ? selection.deselectAll(convertibleRelPaths)
                      : selection.selectAll(convertibleRelPaths),
              child: Text(allHere ? 'Clear' : 'Select all'),
            ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: disabled || selected.isEmpty
                ? null
                : () => ref
                    .read(batchConvertControllerProvider.notifier)
                    .run(selected.toList()),
            style: ElevatedButton.styleFrom(
              backgroundColor: t.accentPrimary,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              'Convert ${selected.length} selected',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// Determinate progress + Cancel, shown in place of the thin single-import
/// bar while a batch runs. `value: done/total` advances 1/n … n/n with the
/// current file's basename (spec-005 AC-5/AC-7).
class BatchProgressBar extends ConsumerWidget {
  const BatchProgressBar({super.key, required this.running});
  final BatchRunning running;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LinearProgressIndicator(
          value: running.total == 0 ? null : running.done / running.total,
          minHeight: 3,
          backgroundColor: t.surfaceSunken,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Converting ${running.done}/${running.total} · '
                  '${basename(running.currentRelPath)}',
                  style: TextStyle(color: t.textPrimary, fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton(
                onPressed: () => ref
                    .read(batchConvertControllerProvider.notifier)
                    .cancel(),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
