import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
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

/// The four buckets [mapPushError] collapses a raw libgit2 push failure
/// into. Exposed via [classifyPushError] so unit tests don't have to
/// fabricate a `git2.Remote` to exercise the mapping.
///
/// - [nonFastForward]: server refused the ref update because the local
///   tip is not a descendant of the remote tip. Expected control flow —
///   drives the conflict UI.
/// - [auth]: HTTP 401/403 during the smart-http handshake, or libgit2's
///   own "authentication required" signal. Also expected control flow —
///   drives the re-auth prompt.
/// - [network]: transport failure before we ever got a reply — DNS,
///   connection refused, TLS, timeout, mid-transfer disconnect. Not
///   mappable to a typed [PushOutcome] per `GitPort` contract
///   ("transport-level errors still throw"); the helper still classifies
///   it so callers can log the category cleanly before rethrow.
/// - [unknown]: anything else. Rethrown unchanged; logs the raw message
///   in debug builds so we can harden the matcher against real failures.
enum PushErrorCategory { nonFastForward, auth, network, unknown }

/// Pure classifier over the raw libgit2 error string.
///
/// Why this is still substring-based: `libgit2dart 1.2.2`'s
/// [git2.LibGit2Error] exposes ONLY `toString()`; the underlying
/// `git_error` struct's `klass` field (which would give us a stable
/// enum — `GIT_ERROR_NET`, `GIT_ERROR_HTTP`, `GIT_ERROR_REFERENCE`, …)
/// is held in a private `Pointer<git_error>` field with no public
/// accessor. Until we migrate off libgit2dart or fork it to expose
/// `klass`/`code`, matching the message is the only option.
///
/// Follow-up (recorded in `docs/Issues.md`, M1a-T10 entry): once a
/// logger port / structured sink lands, the callers of [mapPushError]
/// should emit the raw `error.toString()` at the `unknown` branch so
/// we can harden the patterns against real GitHub failures observed
/// in the field.
///
/// Patterns below are deliberately broad — each bucket lists every
/// known phrasing libgit2 has emitted across 1.0–1.5 plus the HTTP
/// layer's own strings. Order matters: non-fast-forward is checked
/// before auth (the server often sends both a 403 and a
/// "non-fast-forward" hint in the same response); auth is checked
/// before network (a 401 looks like a generic HTTP failure to the
/// network matcher otherwise).
@visibleForTesting
PushErrorCategory classifyPushError(Object error) {
  final msg = error.toString().toLowerCase();

  // --- non-fast-forward ---------------------------------------------------
  // libgit2 native:      "cannot push non-fastforwardable reference"
  // libgit2 <=1.4:       "failed to push some refs"
  // server side-band:    "! [rejected] ...  (non-fast-forward)"
  // helper message:      "updates were rejected because the tip of your
  //                       current branch is behind"
  const nonFastForwardNeedles = <String>[
    'non-fast-forward',
    'not fast-forward',
    'non-fastforwardable',
    'non fastforwardable',
    'cannot push non-fastforwardable',
    '[rejected]',
    'failed to push some refs',
    'tip of your current branch is behind',
    'pushed branch tip is behind',
    // libgit2 1.5 native phrasing observed by
    // integration_test/sync_conflict_test.dart against a file:// bare
    // repo on 2026-04-21. Semantically a fetch-first-then-merge
    // divergence, treated as non-fast-forward.
    'contains commits that are not present locally',
    'reference that you are trying to update on the remote contains',
  ];
  if (nonFastForwardNeedles.any(msg.contains)) {
    return PushErrorCategory.nonFastForward;
  }

  // --- auth ---------------------------------------------------------------
  // libgit2 native:        "authentication required but no callback set"
  //                        "too many redirects or authentication replays"
  //                        "request failed with status code: 401"
  //                        "request failed with status code: 403"
  //                        "unexpected http status code: 401"
  // GitHub smart-http:     "remote: Invalid username or password."
  //                        "fatal: Authentication failed"
  const authNeedles = <String>[
    '401',
    '403',
    'unauthorized',
    'authentication required',
    'authentication replays',
    'authentication failed',
    'invalid username or password',
    'bad credentials',
  ];
  if (authNeedles.any(msg.contains)) {
    return PushErrorCategory.auth;
  }

  // --- network ------------------------------------------------------------
  // libgit2 native (transport.c / winhttp.c / http.c):
  //   "failed to connect to <host>"
  //   "failed to resolve address for <host>"
  //   "failed to send request: ..."
  //   "unexpected disconnection from remote"
  //   "curl error: ... (timeout / could not resolve / …)"
  //   "ssl error: ..."
  //   "timed out"
  //   "connection reset"
  //   "network is unreachable"
  const networkNeedles = <String>[
    'failed to connect',
    'failed to resolve',
    'failed to send request',
    'unexpected disconnection',
    'curl error',
    'ssl error',
    'tls error',
    'timed out',
    'timeout',
    'connection reset',
    'connection refused',
    'network is unreachable',
    'no route to host',
  ];
  if (networkNeedles.any(msg.contains)) {
    return PushErrorCategory.network;
  }

  return PushErrorCategory.unknown;
}

/// Best-effort mapping of libgit2 push errors into the sealed
/// [PushOutcome] types the domain layer understands.
///
/// Returns:
/// - [PushRejectedNonFastForward] when the server rejected the ref update
///   because the local tip is not a descendant of the remote tip.
/// - [PushRejectedAuth] for HTTP 401/403 / libgit2 auth-required failures.
/// - `null` for transport failures (network / TLS / timeout) AND for
///   unrecognised errors — `GitPort.push`'s contract says transport
///   errors throw, so the caller rethrows the original exception in
///   both cases. The split exists so the caller (or a future structured
///   logger) can distinguish classified-but-non-outcome errors from
///   truly unknown ones when hardening the matcher.
///
/// The [remote] parameter is currently informational only; we can't
/// reliably obtain the remote sha without an extra round-trip, so
/// [PushRejectedNonFastForward.remoteSha] is always reported as the
/// empty string. Kept in the signature so a future implementation can
/// call `remote.ls()` / `remote.fetch()` without a breaking change to
/// every caller.
PushOutcome? mapPushError(
  Object error, {
  required git2.Remote remote,
  required String localSha,
}) {
  return pushOutcomeFor(
    classifyPushError(error),
    remoteSha: _safeRemoteSha(remote),
    localSha: localSha,
  );
}

/// Pure dispatch from [PushErrorCategory] to the sealed [PushOutcome]
/// hierarchy. Split out of [mapPushError] so unit tests can exercise
/// every branch without constructing a live [git2.Remote] — the
/// `git2.Remote.*` constructors all require a loaded libgit2 FFI lib,
/// which is not available under `fvm flutter test` on the Windows host.
@visibleForTesting
PushOutcome? pushOutcomeFor(
  PushErrorCategory category, {
  required String remoteSha,
  required String localSha,
}) {
  switch (category) {
    case PushErrorCategory.nonFastForward:
      return PushRejectedNonFastForward(
        remoteSha: remoteSha,
        localSha: localSha,
      );
    case PushErrorCategory.auth:
      return const PushRejectedAuth();
    case PushErrorCategory.network:
    case PushErrorCategory.unknown:
      return null;
  }
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
