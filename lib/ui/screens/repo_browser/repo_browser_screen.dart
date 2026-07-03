import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/controllers/batch_spec_importer.dart';
import '../../../app/controllers/repo_browser_controller.dart';
import '../../../app/controllers/spec_importer.dart';
import '../../../app/providers/spec_import_providers.dart';
import '../../../app/providers/spec_providers.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../spec_reader_md/spec_reader_md_screen.dart';
import '../spec_reader_pdf/spec_reader_pdf_screen.dart';
import '../spec_reader_svg/spec_reader_svg_screen.dart';
import 'batch_convert_bar.dart';

/// Repo-file browser for the "convert existing .md / .pdf → spec" flow.
/// Rooted at the current workdir. The user navigates folders + picks a
/// `.md` or `.pdf`; the screen pops once the importer commits and returns.
///
/// Listens to [specImportControllerProvider]: on success, shows a
/// confirmation SnackBar (the JobList screen handles list invalidation +
/// its own SnackBar) and pops. On failure, shows the message inline so
/// the user can pick a different file without losing position.
class RepoBrowserScreen extends ConsumerStatefulWidget {
  const RepoBrowserScreen({super.key});

  @override
  ConsumerState<RepoBrowserScreen> createState() => _RepoBrowserScreenState();
}

class _RepoBrowserScreenState extends ConsumerState<RepoBrowserScreen> {
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final async = ref.watch(repoBrowserControllerProvider);
    final importState = ref.watch(specImportControllerProvider);
    final batchState = ref.watch(batchConvertControllerProvider);

    ref.listen<AsyncValue<SpecImportOutcome?>>(specImportControllerProvider,
        (prev, next) {
      final outcome = next.value;
      if (outcome is SpecImportSuccess && mounted) {
        Navigator.of(context).maybePop();
      }
    });

    // Batch convert terminates in-place (no pop): show a one-shot summary
    // SnackBar and clear the selection. The JobList picks up the new rows
    // via the invalidation the controller already fired.
    ref.listen<BatchConvertState>(batchConvertControllerProvider,
        (prev, next) {
      if (next is! BatchFinished || !mounted) return;
      final total = prev is BatchRunning ? prev.total : null;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
        content: Text(_batchSummary(next, total)),
        duration: const Duration(seconds: 4),
      ));
      ref.read(repoSelectionControllerProvider.notifier).clear();
    });

    return ColoredBox(
      color: t.surfaceBackground,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _TopChrome(async: async),
          Expanded(
            child: _Body(
              async: async,
              importState: importState,
              batchState: batchState,
            ),
          ),
        ],
      ),
    );
  }
}

/// Human summary for a finished batch. On cancel it names how many files
/// were left unconverted (AC-6/AC-7).
String _batchSummary(BatchFinished f, int? total) {
  final converted = f.converted.length;
  if (f.cancelled) {
    final notRun = total == null ? null : total - converted - f.failures.length;
    final tail = notRun == null || notRun <= 0 ? '' : ' — $notRun not run';
    return 'Converted $converted, cancelled$tail';
  }
  return 'Converted $converted, ${f.failures.length} failed';
}

class _TopChrome extends ConsumerWidget {
  const _TopChrome({required this.async});
  final AsyncValue<RepoBrowserState> async;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final state = async.value;
    final crumb = state == null || state.isAtRoot
        ? '<repo root>'
        : state.currentRelPath;
    final canGoUp = state != null && !state.isAtRoot;
    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: t.surfaceElevated,
        border: Border(bottom: BorderSide(color: t.borderSubtle)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 20),
            tooltip: 'Close',
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.arrow_upward_rounded, size: 18),
            tooltip: 'Up',
            onPressed: canGoUp
                ? () =>
                    ref.read(repoBrowserControllerProvider.notifier).up()
                : null,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              crumb,
              style: appMono(
                context,
                size: 13,
                weight: FontWeight.w500,
                color: t.textPrimary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'pick a .md or .pdf to convert',
            style: TextStyle(color: t.textMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({
    required this.async,
    required this.importState,
    required this.batchState,
  });
  final AsyncValue<RepoBrowserState> async;
  final AsyncValue<SpecImportOutcome?> importState;
  final BatchConvertState batchState;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final placeholder = _placeholder(context);
    if (placeholder != null) return placeholder;
    return _ready(context, ref, async.value!);
  }

  /// Loading / error / no-repo / null states, or null once a directory
  /// listing is ready to render.
  Widget? _placeholder(BuildContext context) {
    final t = context.tokens;
    if (async.isLoading && !async.hasValue) {
      return const Center(child: CircularProgressIndicator());
    }
    if (async.hasError && !async.hasValue) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Failed to read directory: ${async.error}',
            style: TextStyle(color: t.statusDanger, fontSize: 13),
          ),
        ),
      );
    }
    final state = async.value;
    if (state is RepoBrowserUnavailable) {
      return Center(
        child: Text(
          'No repository selected.',
          style: TextStyle(color: t.textMuted, fontSize: 13),
        ),
      );
    }
    if (state == null) return const Center(child: CircularProgressIndicator());
    return null;
  }

  Widget _ready(BuildContext context, WidgetRef ref, RepoBrowserState state) {
    final batchRunning = batchState is BatchRunning;
    final disabled = importState.isLoading || batchRunning;
    final selected = ref.watch(repoSelectionControllerProvider);
    final convertibleRelPaths = [
      for (final e in state.entries)
        if (_isConvertible(e)) e.relPath,
    ];
    return Column(
      children: [
        if (importState.value is SpecImportFailure)
          _FailureBanner(
            message: (importState.value as SpecImportFailure).message,
            onDismiss: () =>
                ref.read(specImportControllerProvider.notifier).cancel(),
          ),
        if (batchRunning)
          BatchProgressBar(running: batchState as BatchRunning)
        else if (importState.isLoading)
          const LinearProgressIndicator(minHeight: 2),
        if (selected.isNotEmpty && !batchRunning)
          SelectionActionBar(
            convertibleRelPaths: convertibleRelPaths,
            disabled: disabled,
          ),
        Expanded(
          child: state.entries.isEmpty
              ? _EmptyState(isRoot: state.isAtRoot)
              : _EntryList(entries: state.entries, disabled: disabled),
        ),
      ],
    );
  }
}

/// A row is convertible iff it is a file whose name is not `.svg` — the
/// exact rule the single-convert button uses (SVG is non-annotatable,
/// spec-002). Directories and `.svg` files get no checkbox.
bool _isConvertible(RepoBrowserEntry e) =>
    !e.isDirectory && !e.name.toLowerCase().endsWith('.svg');

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.isRoot});
  final bool isRoot;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.folder_off_outlined, size: 32, color: t.textMuted),
          const SizedBox(height: 10),
          Text(
            isRoot
                ? 'Repo has no markdown or PDF files here.'
                : 'No markdown or PDF here.',
            style: TextStyle(color: t.textMuted, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _EntryList extends ConsumerWidget {
  const _EntryList({required this.entries, required this.disabled});
  final List<RepoBrowserEntry> entries;
  final bool disabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: entries.length,
      separatorBuilder: (_, _) =>
          Divider(height: 1, thickness: 1, color: t.borderSubtle),
      itemBuilder: (ctx, i) {
        final e = entries[i];
        if (e.isDirectory) {
          return _DirectoryRow(
            entry: e,
            onTap: disabled
                ? null
                : () => ref
                    .read(repoBrowserControllerProvider.notifier)
                    .enter(e.relPath),
          );
        }
        return _FileRow(
          entry: e,
          disabled: disabled,
          onConvert: disabled
              ? null
              : () => ref
                  .read(specImportControllerProvider.notifier)
                  .run(e.relPath),
          onOpen: disabled ? null : () => _openFile(ctx, ref, e.relPath),
        );
      },
    );
  }

  void _openFile(BuildContext context, WidgetRef ref, String relPath) {
    final workdir = ref.read(currentWorkdirProvider);
    if (workdir == null) return;
    final screen = readerScreenForBrowserPath(
      workdir: workdir,
      relPath: relPath,
    );
    if (screen == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => Scaffold(body: screen)),
    );
  }
}

/// Pure dispatch: pick the right reader screen for a repo-browser entry
/// based on the lowercased extension. Returns null for unsupported types
/// so callers can ignore the tap. Spec-002 Milestone A.
///
/// Exposed at library scope so widget tests can exercise the dispatch
/// without mounting the full browser tree.
Widget? readerScreenForBrowserPath({
  required String workdir,
  required String relPath,
}) {
  final absPath = '$workdir/$relPath';
  final lower = relPath.toLowerCase();
  if (lower.endsWith('.md') || lower.endsWith('.markdown')) {
    return SpecReaderMdScreen.fromPath(filePath: absPath);
  }
  if (lower.endsWith('.pdf')) {
    return SpecReaderPdfScreen(filePath: absPath);
  }
  if (lower.endsWith('.svg')) {
    return SpecReaderSvgScreen(filePath: absPath);
  }
  return null;
}

class _DirectoryRow extends StatelessWidget {
  const _DirectoryRow({required this.entry, required this.onTap});
  final RepoBrowserEntry entry;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Material(
      color: t.surfaceBackground,
      child: InkWell(
        onTap: onTap,
        hoverColor: t.surfaceSunken,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              Icon(Icons.folder_rounded, size: 18, color: t.accentPrimary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  entry.name,
                  style: appMono(
                    context,
                    size: 13,
                    weight: FontWeight.w500,
                    color: t.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(Icons.chevron_right_rounded, size: 18, color: t.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class _FileRow extends StatelessWidget {
  const _FileRow({
    required this.entry,
    required this.disabled,
    required this.onConvert,
    required this.onOpen,
  });
  final RepoBrowserEntry entry;

  /// Disables the leading checkbox while an import / batch is in flight
  /// (AC-11). The convert / open callbacks are already null in that state.
  final bool disabled;
  final VoidCallback? onConvert;

  /// Spec-002 Milestone A: tapping the row body opens the appropriate
  /// reader. Null when the controller is in a disabled state (e.g. an
  /// import is in flight).
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final isSvg = entry.name.toLowerCase().endsWith('.svg');
    return Material(
      color: t.surfaceBackground,
      child: InkWell(
        onTap: onOpen,
        hoverColor: t.surfaceSunken,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 10, 12, 10),
          child: Row(
            children: [
              // Convertible rows carry a leading checkbox for batch select;
              // `.svg` rows are non-convertible so get an equal-width spacer
              // to keep the description icons aligned (AC-1).
              if (isSvg)
                const SizedBox(width: 40)
              else
                _RowCheckbox(relPath: entry.relPath, disabled: disabled),
              Icon(Icons.description_outlined, size: 18, color: t.textMuted),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.name,
                      style: appMono(
                        context,
                        size: 13,
                        weight: FontWeight.w500,
                        color: t.textPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      entry.relPath,
                      style: TextStyle(
                        color: t.textMuted,
                        fontSize: 11,
                        height: 1.4,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // SVG files are non-annotatable (spec-002) — hide the
              // convert-to-spec action; the file is read-only.
              if (!isSvg)
                ElevatedButton(
                  onPressed: onConvert,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: t.accentPrimary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6)),
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text(
                    'Convert to spec',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Leading checkbox for a convertible file row. Watches only its own
/// membership in the selection set (`select((s) => s.contains(relPath))`)
/// so ticking one row never rebuilds the whole list (spec-005 §9).
class _RowCheckbox extends ConsumerWidget {
  const _RowCheckbox({required this.relPath, required this.disabled});
  final String relPath;
  final bool disabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(
      repoSelectionControllerProvider.select((s) => s.contains(relPath)),
    );
    return SizedBox(
      width: 40,
      child: Checkbox(
        value: selected,
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        onChanged: disabled
            ? null
            : (_) => ref
                .read(repoSelectionControllerProvider.notifier)
                .toggle(relPath),
      ),
    );
  }
}

class _FailureBanner extends StatelessWidget {
  const _FailureBanner({required this.message, required this.onDismiss});
  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: t.statusDanger.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: t.statusDanger.withValues(alpha: 0.30)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, size: 16, color: t.statusDanger),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: t.statusDanger,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 16),
            splashRadius: 16,
            color: t.statusDanger,
            onPressed: onDismiss,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 24, height: 24),
          ),
        ],
      ),
    );
  }
}
