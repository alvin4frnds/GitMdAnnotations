import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/services/changelog_aggregator.dart';
import '../providers/spec_providers.dart';

/// Sealed UI-level state for the ChangelogViewer screen. Mirrors the
/// JobList controller's shape (IMPLEMENTATION.md §4.3) — exhaustive
/// `switch` in the widget tree. Loading / error live on the surrounding
/// [AsyncValue].
sealed class ChangelogViewerState {
  const ChangelogViewerState();
}

/// No repo / workdir selected yet. Screen renders the same muted empty
/// chrome JobList uses.
class ChangelogViewerEmpty extends ChangelogViewerState {
  const ChangelogViewerEmpty();
}

/// Timeline resolved. [entries] is newest-first and may be empty (valid:
/// the repo has open jobs but none have a `## Changelog` section yet).
class ChangelogViewerLoaded extends ChangelogViewerState {
  const ChangelogViewerLoaded(this.entries);
  final List<DatedChangelogEntry> entries;
}

/// Wires [ChangelogAggregator] into a Riverpod `AsyncNotifier`. Rebuilt
/// whenever [currentRepoProvider] or the underlying [specRepositoryProvider]
/// changes so RepoPicker can flip the source transparently.
class ChangelogViewerController
    extends AsyncNotifier<ChangelogViewerState> {
  @override
  Future<ChangelogViewerState> build() async {
    final repo = ref.watch(currentRepoProvider);
    final spec = ref.watch(specRepositoryProvider);
    if (repo == null || spec == null) return const ChangelogViewerEmpty();
    final entries = await ChangelogAggregator(spec).allChangelogs(repo);
    return ChangelogViewerLoaded(entries);
  }

  /// Re-runs aggregation. Transitions state through `loading` so the UI
  /// can show a spinner. Errors are captured by [AsyncValue.guard].
  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(build);
  }
}
