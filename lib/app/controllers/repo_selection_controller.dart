import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Holds the set of repo-relative paths the user has ticked for a batch
/// "Convert to spec" in the repo browser. Keyed by [RepoBrowserEntry.relPath]
/// (repo-relative, forward-slash, unique).
///
/// Deliberately dumb: it knows nothing about conversion, directories, or
/// `.svg` filtering — callers decide which relPaths are convertible before
/// handing them in. Selection is **not** cleared on directory navigation
/// (spec-005 OQ-1) so a user can tick files across folders and convert the
/// union in one go; only [clear] (post-batch or explicit user action) empties
/// it.
///
/// `autoDispose` so it dies with the browser route, matching every other
/// scoped-session notifier in the app.
class RepoSelectionController extends AutoDisposeNotifier<Set<String>> {
  @override
  Set<String> build() => const {};

  bool isSelected(String relPath) => state.contains(relPath);

  void toggle(String relPath) {
    final next = Set<String>.of(state);
    if (!next.remove(relPath)) next.add(relPath);
    state = Set.unmodifiable(next);
  }

  /// Union the current selection with [relPaths] (used by "Select all" over
  /// the current directory's convertible entries).
  void selectAll(Iterable<String> relPaths) {
    state = Set.unmodifiable(Set<String>.of(state)..addAll(relPaths));
  }

  /// Remove exactly [relPaths] from the selection (used when "Select all"
  /// flips to "Clear" for the current directory).
  void deselectAll(Iterable<String> relPaths) {
    state = Set.unmodifiable(Set<String>.of(state)..removeAll(relPaths));
  }

  void clear() {
    if (state.isEmpty) return;
    state = const {};
  }
}
