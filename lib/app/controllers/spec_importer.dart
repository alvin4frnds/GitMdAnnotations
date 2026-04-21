import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/commit.dart';
import '../../domain/entities/git_identity.dart';
import '../../domain/entities/job_ref.dart';
import '../../domain/entities/repo_ref.dart';
import '../../domain/ports/clock_port.dart';
import '../../domain/ports/file_system_port.dart';
import '../../domain/ports/git_port.dart';
import '../providers/annotation_providers.dart';
import '../providers/auth_providers.dart';
import '../providers/spec_providers.dart';
import '../providers/sync_providers.dart';
import 'auth_controller.dart';

/// Pure-domain service that copies a markdown file from anywhere in the
/// repo working tree into a new `jobs/pending/spec-<id>/02-spec.md` and
/// commits it to the `claude-jobs` sidecar branch.
///
/// Provenance (the source repo-relative path + timestamp) is embedded as
/// HTML comments at the top of the copied `02-spec.md`, which survives in
/// git, renders invisibly, and leaves [parseChangelog] alone since that
/// parser only scans after `## Changelog`.
class SpecImporter {
  const SpecImporter({
    required FileSystemPort fs,
    required GitPort git,
    required Clock clock,
  })  : _fs = fs,
        _git = git,
        _clock = clock;

  final FileSystemPort _fs;
  final GitPort _git;
  final Clock _clock;

  Future<SpecImportOutcome> importFromRepoPath({
    required String sourceRelPath,
    required RepoRef repo,
    required String workdir,
    required GitIdentity identity,
  }) async {
    final normalized = _stripLeadingSlash(sourceRelPath);
    if (normalized.startsWith('jobs/pending/')) {
      return const SpecImportFailure(
        "That file is already inside jobs/pending — pick a source outside the specs folder.",
      );
    }
    final String contents;
    try {
      contents = await _fs.readString('$workdir/$normalized');
    } on FsNotFound {
      return SpecImportFailure('File not found: $normalized');
    } on FsNotAFile {
      return SpecImportFailure('Not a file: $normalized');
    } on FsError catch (e) {
      return SpecImportFailure("Couldn't read $normalized: $e", cause: e);
    }

    final base = basename(normalized);
    final baseSlug = slugify(base);
    final jobId = await _resolveCollision(baseSlug, workdir);
    final composed = _composeSpec(
      sourceRelPath: normalized,
      contents: contents,
    );

    try {
      final commit = await _git.commit(
        files: [
          FileWrite(
            path: 'jobs/pending/$jobId/02-spec.md',
            contents: composed,
          ),
        ],
        message: 'Import $normalized as $jobId',
        id: identity,
        branch: 'claude-jobs',
      );
      return SpecImportSuccess(
        job: JobRef(repo: repo, jobId: jobId),
        commit: commit,
      );
    } on GitError catch (e) {
      return SpecImportFailure('Commit failed: $e', cause: e);
    }
  }

  String _composeSpec({
    required String sourceRelPath,
    required String contents,
  }) {
    final at = _clock.now().toUtc().toIso8601String();
    final buf = StringBuffer()
      ..writeln('<!-- gitmdscribe:imported-from=$sourceRelPath -->')
      ..writeln('<!-- gitmdscribe:imported-at=$at -->')
      ..writeln();
    buf.write(contents);
    return buf.toString();
  }

  Future<String> _resolveCollision(String baseSlug, String workdir) async {
    if (!await _fs.exists('$workdir/jobs/pending/$baseSlug')) {
      return baseSlug;
    }
    for (var n = 2; n < 10000; n++) {
      final candidate = '$baseSlug-$n';
      if (!await _fs.exists('$workdir/jobs/pending/$candidate')) {
        return candidate;
      }
    }
    throw StateError('Could not find a free jobId near $baseSlug');
  }

  static String _stripLeadingSlash(String p) =>
      p.startsWith('/') ? p.substring(1) : p;
}

/// Derive a valid `spec-<id>` slug from a filename. Always satisfies
/// `^spec-[a-z0-9-]+$` (see `JobRef._pattern`).
String slugify(String filename) {
  final stem = filename.replaceFirst(
    RegExp(r'\.(md|markdown)$', caseSensitive: false),
    '',
  );
  final lowered = stem.toLowerCase();
  final replaced = lowered.replaceAll(RegExp(r'[^a-z0-9]+'), '-');
  final collapsed =
      replaced.replaceAll(RegExp(r'-+'), '-').replaceAll(RegExp(r'^-|-$'), '');
  final core = collapsed.isEmpty ? 'imported' : collapsed;
  return 'spec-$core';
}

String basename(String path) {
  final slash = path.lastIndexOf('/');
  return slash < 0 ? path : path.substring(slash + 1);
}

/// Sealed outcome surface for the importer. Errors that the user can act on
/// flow through [SpecImportFailure]; only programmer-error throws escape.
sealed class SpecImportOutcome {
  const SpecImportOutcome();
}

class SpecImportSuccess extends SpecImportOutcome {
  const SpecImportSuccess({required this.job, required this.commit});
  final JobRef job;
  final Commit commit;
}

class SpecImportCancelled extends SpecImportOutcome {
  const SpecImportCancelled();
}

class SpecImportFailure extends SpecImportOutcome {
  const SpecImportFailure(this.message, {this.cause});
  final String message;
  final Object? cause;
}

/// Riverpod controller. Holds the most-recent outcome (or null when idle).
/// Widgets `ref.listen` this to drive SnackBars + JobList invalidation.
class SpecImportController
    extends AutoDisposeNotifier<AsyncValue<SpecImportOutcome?>> {
  @override
  AsyncValue<SpecImportOutcome?> build() => const AsyncValue.data(null);

  Future<void> run(String sourceRelPath) async {
    if (state.isLoading) return;
    final repo = ref.read(currentRepoProvider);
    final workdir = ref.read(currentWorkdirProvider);
    if (repo == null || workdir == null) {
      state = const AsyncValue.data(
        SpecImportFailure('Open a repository first.'),
      );
      return;
    }
    state = const AsyncValue.loading();
    try {
      final auth = await ref.read(authControllerProvider.future);
      if (auth is! AuthSignedIn) {
        state = const AsyncValue.data(
          SpecImportFailure('Sign in before importing a spec.'),
        );
        return;
      }
      final importer = SpecImporter(
        fs: ref.read(fileSystemProvider),
        git: ref.read(gitPortProvider),
        clock: ref.read(clockProvider),
      );
      final outcome = await importer.importFromRepoPath(
        sourceRelPath: sourceRelPath,
        repo: repo,
        workdir: workdir,
        identity: auth.session.identity,
      );
      state = AsyncValue.data(outcome);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  void cancel() {
    state = const AsyncValue.data(SpecImportCancelled());
  }
}
