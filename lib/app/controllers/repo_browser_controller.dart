import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/ports/file_system_port.dart';
import '../providers/spec_providers.dart';

/// One row in the repo-file browser — either a directory the user can
/// enter or a `.md` file they can convert to a spec.
class RepoBrowserEntry {
  const RepoBrowserEntry({
    required this.name,
    required this.relPath,
    required this.isDirectory,
  });

  final String name;

  /// Path relative to the repo root (workdir). Forward slashes only.
  final String relPath;
  final bool isDirectory;
}

class RepoBrowserState {
  const RepoBrowserState({
    required this.currentRelPath,
    required this.entries,
  });

  /// Repo-relative path of the directory currently shown. Empty string
  /// for the repo root.
  final String currentRelPath;
  final List<RepoBrowserEntry> entries;

  bool get isAtRoot => currentRelPath.isEmpty;
}

class RepoBrowserUnavailable extends RepoBrowserState {
  const RepoBrowserUnavailable()
      : super(currentRelPath: '', entries: const []);
}

/// Holds the directory currently being browsed. Re-lists on every
/// navigation so a sync-down that mutates disk is reflected on the next
/// [enter] / [up] / [refresh] call.
class RepoBrowserController extends AutoDisposeAsyncNotifier<RepoBrowserState> {
  static const _hiddenTopLevel = {
    '.git',
    '.gitmdscribe-backups',
  };

  @override
  Future<RepoBrowserState> build() async {
    final workdir = ref.watch(currentWorkdirProvider);
    if (workdir == null) return const RepoBrowserUnavailable();
    final fs = ref.watch(fileSystemProvider);
    return _list(fs, workdir, '');
  }

  Future<void> enter(String childRelPath) async {
    final workdir = ref.read(currentWorkdirProvider);
    if (workdir == null) return;
    final fs = ref.read(fileSystemProvider);
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _list(fs, workdir, childRelPath));
  }

  Future<void> up() async {
    final current = state.value;
    if (current == null || current.isAtRoot) return;
    final idx = current.currentRelPath.lastIndexOf('/');
    final parent = idx < 0 ? '' : current.currentRelPath.substring(0, idx);
    await enter(parent);
  }

  Future<void> refresh() async {
    final current = state.value;
    await enter(current?.currentRelPath ?? '');
  }

  Future<RepoBrowserState> _list(
    FileSystemPort fs,
    String workdir,
    String relPath,
  ) async {
    final dir = relPath.isEmpty ? workdir : '$workdir/$relPath';
    List<FsEntry> raw;
    try {
      raw = await fs.listDir(dir);
    } on FsNotFound {
      raw = const [];
    }
    final kept = <RepoBrowserEntry>[];
    for (final e in raw) {
      if (!_isVisible(relPath, e)) continue;
      final childRel = relPath.isEmpty ? e.name : '$relPath/${e.name}';
      kept.add(RepoBrowserEntry(
        name: e.name,
        relPath: childRel,
        isDirectory: e.isDirectory,
      ));
    }
    kept.sort((a, b) {
      if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return RepoBrowserState(currentRelPath: relPath, entries: kept);
  }

  bool _isVisible(String parentRel, FsEntry e) {
    final name = e.name;
    if (name.startsWith('.')) return false;
    if (parentRel.isEmpty && _hiddenTopLevel.contains(name)) return false;
    if (parentRel.isEmpty && name == 'jobs') {
      // Still navigable, but the browser hides already-imported specs
      // beneath jobs/pending. Leave the `jobs` folder visible so users can
      // see other job subtrees (e.g. jobs/archived) if they exist.
      return true;
    }
    if (parentRel == 'jobs' && name == 'pending') return false;
    if (e.isDirectory) return true;
    final lower = name.toLowerCase();
    return lower.endsWith('.md') || lower.endsWith('.markdown');
  }
}
