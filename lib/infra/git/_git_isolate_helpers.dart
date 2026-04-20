import 'dart:io';

import 'package:libgit2dart/libgit2dart.dart' as git2;

import '../../domain/ports/git_port.dart';

/// Builds the libgit2 [git2.Callbacks] struct for remote operations. When
/// [token] is null we return empty callbacks; libgit2 will surface an
/// auth error which we map downstream. When present, we wire HTTPS basic
/// auth with `x-access-token` as the username — that's the convention
/// GitHub accepts for OAuth access tokens and PATs alike.
git2.Callbacks buildCallbacks(String? token) {
  if (token == null || token.isEmpty) return const git2.Callbacks();
  return git2.Callbacks(
    credentials: git2.UserPass(username: 'x-access-token', password: token),
  );
}

/// Checkout [branch] on [repo] and move HEAD to it. Equivalent to
/// `git checkout <branch>` — leaves the working tree in the branch's
/// tree state. If the branch doesn't exist locally this throws the
/// underlying libgit2 error; callers are expected to only ask for
/// branches they've already created or fetched.
void checkoutBranch(git2.Repository repo, String branch) {
  final refName = 'refs/heads/$branch';
  final current = repo.head;
  if (current.name == refName) return;
  git2.Checkout.reference(
    repo: repo,
    name: refName,
    strategy: const {git2.GitCheckout.safe, git2.GitCheckout.recreateMissing},
  );
  repo.setHead(refName);
}

/// Recursive directory copy. When [skipDotGit] is true the `.git`
/// sub-directory is skipped — appropriate for working-tree backups
/// where we only want the visible files.
Future<void> copyDirectory(
  Directory source,
  Directory dest, {
  bool skipDotGit = false,
}) async {
  if (!await dest.exists()) {
    await dest.create(recursive: true);
  }
  await for (final entity in source.list(followLinks: false)) {
    final name = entity.uri.pathSegments
        .lastWhere((s) => s.isNotEmpty, orElse: () => '');
    if (skipDotGit && name == '.git') continue;
    final destPath = '${dest.path}${Platform.pathSeparator}$name';
    if (entity is File) {
      await entity.copy(destPath);
    } else if (entity is Directory) {
      await copyDirectory(entity, Directory(destPath), skipDotGit: false);
    }
  }
}

/// Best-effort mapping of libgit2 push errors into the sealed
/// [PushOutcome] types the domain layer understands.
///
/// libgit2's push path only raises `LibGit2Error` with a message string;
/// the common buckets we care about are:
///   * "cannot push non-fastforwardable reference" / "non-fast-forward"
///     -> [PushRejectedNonFastForward]
///   * HTTP 401 / 403 during the smart-http handshake
///     -> [PushRejectedAuth]
///
/// If we can't confidently map, we return `null` so the caller rethrows.
PushOutcome? mapPushError(
  Object error, {
  required git2.Remote remote,
  required String localSha,
}) {
  final msg = error.toString().toLowerCase();
  if (msg.contains('non-fast-forward') ||
      msg.contains('not fast-forward') ||
      msg.contains('cannot push non-fastforwardable') ||
      msg.contains('rejected')) {
    return PushRejectedNonFastForward(
      remoteSha: _safeRemoteSha(remote),
      localSha: localSha,
    );
  }
  if (msg.contains('401') ||
      msg.contains('403') ||
      msg.contains('unauthorized') ||
      msg.contains('authentication')) {
    return const PushRejectedAuth();
  }
  return null;
}

String _safeRemoteSha(git2.Remote remote) {
  try {
    // Without a fresh fetch we can't know the remote sha for certain; the
    // field is informational only. Returning an empty string is safer
    // than guessing.
    return '';
  } catch (_) {
    return '';
  }
}
