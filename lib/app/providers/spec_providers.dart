import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/job_ref.dart';
import '../../domain/entities/repo_ref.dart';
import '../../domain/entities/source_kind.dart';
import '../../domain/entities/spec_file.dart';
import '../../domain/ports/file_system_port.dart';
import '../../domain/services/spec_repository.dart';
import '../controllers/changelog_viewer_controller.dart';
import '../controllers/job_list_controller.dart';

/// Binds the [FileSystemPort] implementation at composition root. Tests
/// override with a [FakeFileSystem]; `bootstrap.dart` wires the production
/// [FsAdapter] in `real` mode.
final fileSystemProvider = Provider<FileSystemPort>((ref) {
  throw UnimplementedError(
    'fileSystemProvider must be overridden at composition root',
  );
});

/// The current repo root the app is operating against on disk. Null when
/// no repo has been picked yet. M1a leaves this as a const default for
/// mockup mode and null for real mode (RepoPicker ships in M1c).
final currentWorkdirProvider = StateProvider<String?>((ref) => null);

/// Composed [SpecRepository] anchored at [currentWorkdirProvider]. Null
/// when no workdir is set so [JobListController] can surface an empty
/// state without swallowing the "missing workdir" signal.
final specRepositoryProvider = Provider<SpecRepository?>((ref) {
  final fs = ref.watch(fileSystemProvider);
  final workdir = ref.watch(currentWorkdirProvider);
  if (workdir == null) return null;
  return SpecRepository(fs: fs, workdir: workdir);
});

/// The currently-selected [RepoRef]. Null when no repo has been picked.
/// RepoPicker will set this in M1c; M1a wires a fixed demo RepoRef in
/// mockup mode so the JobList screen has something to show.
final currentRepoProvider = StateProvider<RepoRef?>((ref) => null);

/// UI-facing job list state machine. See [JobListController].
final jobListControllerProvider =
    AsyncNotifierProvider<JobListController, JobListState>(
  JobListController.new,
);

/// UI-facing changelog-timeline state machine. See
/// [ChangelogViewerController]. Scoped off the same `currentRepoProvider` /
/// `currentWorkdirProvider` pair as [jobListControllerProvider] so a
/// RepoPicker swap re-aggregates automatically.
final changelogViewerControllerProvider =
    AsyncNotifierProvider<ChangelogViewerController, ChangelogViewerState>(
  ChangelogViewerController.new,
);

/// Loads the [SpecFile] for a single [JobRef] from the current
/// [SpecRepository]. Null when no workdir is set (mirrors
/// [specRepositoryProvider] so callers don't have to handle two null
/// layers). Async because [SpecRepository.loadSpec] reads from disk —
/// tests override via `fileSystemProvider.overrideWithValue(...)` +
/// `currentWorkdirProvider.overrideWith((_) => '/workdir')` and seed the
/// spec with `fs.seedFile(...)`.
///
/// Used by the Review-panel orchestrator to fetch the exact spec
/// snapshot used for Submit / Approve composition.
final specFileProvider = FutureProvider.autoDispose.family<SpecFile?, JobRef>(
  (ref, job) async {
    final repo = ref.watch(specRepositoryProvider);
    if (repo == null) return null;
    return repo.loadSpec(job);
  },
);

/// Loads a [SpecFile] from an absolute filesystem path, bypassing the
/// job-pending-folder convention used by [specFileProvider]. Used by the
/// repo browser when the user taps a `.md`/`.markdown` file that isn't a
/// tracked spec — spec-002 Milestone A. Source kind is markdown by
/// construction (only `.md` reaches this path; the browser dispatches
/// `.pdf` / `.svg` to their dedicated readers).
final specFileByPathProvider =
    FutureProvider.autoDispose.family<SpecFile, String>(
  (ref, absPath) async {
    final fs = ref.watch(fileSystemProvider);
    final contents = await fs.readString(absPath);
    return SpecFile(
      path: absPath,
      sha: _pathShaOf(contents),
      contents: contents,
      sourceKind: SourceKind.markdown,
    );
  },
);

// Deterministic content-hash; mirrors SpecRepository._contentSha (FNV-1a
// x5 concatenated). Browser-flow edits don't have a real git blob SHA
// until they commit — this placeholder keeps SpecFile's non-empty
// invariant satisfied and the SHA stable across reads.
String _pathShaOf(String contents) {
  const salts = <int>[
    0x00000000, 0x9E3779B1, 0x85EBCA77, 0xC2B2AE3D, 0x27D4EB2F,
  ];
  const mask32 = 0xFFFFFFFF;
  const fnvPrime32 = 0x01000193;
  final bytes = contents.codeUnits;
  final buf = StringBuffer();
  for (final salt in salts) {
    var h = (0x811C9DC5 ^ salt) & mask32;
    for (final b in bytes) {
      h = (h ^ (b & 0xff)) & mask32;
      h = (h * fnvPrime32) & mask32;
    }
    buf.write(h.toRadixString(16).padLeft(8, '0'));
  }
  return buf.toString();
}
