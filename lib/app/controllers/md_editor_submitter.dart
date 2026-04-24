import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/commit.dart';
import '../../domain/entities/git_identity.dart';
import '../../domain/ports/git_port.dart';
import '../providers/sync_providers.dart';

/// Stateless commit pipeline for the spec-002 Milestone B markdown editor.
///
/// Job-flow edits (e.g. user is reviewing `jobs/pending/<id>/02-spec.md`)
/// pass [jobFlowBranch] = `'claude-jobs'`, matching the review/approve
/// commits the tablet already lands there. Browser-flow edits (user
/// opened a `.md` via the repo browser) pass `null` — the submitter
/// reads [GitPort.currentBranch] so the commit lands on whatever branch
/// the user already has checked out (per spec-002 §6: "I'm editing what
/// I see").
class MdEditorSubmitter {
  const MdEditorSubmitter({required this.git});

  final GitPort git;

  /// Commits [newContents] to [absSpecPath] as a single file write.
  ///
  /// [workdir] is the current repo root; the submitter strips this prefix
  /// from [absSpecPath] to build a repo-relative path for [FileWrite].
  /// Returns the resulting commit. Callers are responsible for
  /// not calling [submit] when nothing has changed (the UI's dirty gate
  /// handles this) — an unchanged save here would produce an empty-diff
  /// commit, which libgit2 still records.
  Future<Commit> submit({
    required String workdir,
    required String absSpecPath,
    required String newContents,
    required GitIdentity identity,
    String? jobFlowBranch,
  }) async {
    final relPath = _toRepoRelative(workdir, absSpecPath);
    final branch = jobFlowBranch ?? await git.currentBranch();
    final write = FileWrite(path: relPath, contents: newContents);
    return git.commit(
      files: [write],
      message: 'Edit ${_basename(relPath)}',
      id: identity,
      branch: branch,
    );
  }

  static String _toRepoRelative(String workdir, String absPath) {
    final w = workdir.replaceAll('\\', '/');
    final a = absPath.replaceAll('\\', '/');
    if (!a.startsWith(w)) {
      // Path isn't under the workdir — commit it verbatim (libgit2 will
      // reject paths outside the tree). Shouldn't happen via the UI
      // since absSpecPath is always built from `$workdir/<relPath>`.
      return a;
    }
    final tail = a.substring(w.length);
    return tail.startsWith('/') ? tail.substring(1) : tail;
  }

  static String _basename(String path) {
    final slash = path.lastIndexOf(RegExp(r'[/\\]'));
    return slash < 0 ? path : path.substring(slash + 1);
  }
}

/// DI-friendly provider for the editor submitter. Overrides `gitPortProvider`
/// propagate through automatically (tests wire `FakeGitPort`).
final mdEditorSubmitterProvider = Provider<MdEditorSubmitter>((ref) {
  return MdEditorSubmitter(git: ref.watch(gitPortProvider));
});
