import 'dart:developer' as developer;

import '../domain/entities/repo_ref.dart';
import '../domain/ports/secure_storage_port.dart';

/// Snapshot of "where the user left off" persisted across cold starts.
///
/// The triple [(repo, workdir, jobId)] is the minimum metadata needed to
/// skip the RepoPicker → `GET /user/repos` round-trip that the NFR-2
/// cold-start budget (§7: 2 s online / 3 s offline) can't absorb on LTE.
///
/// - [repo] + [workdir] are persisted together on every successful
///   [RepoPickerController.pick] — rehydrating one without the other is a
///   no-op because [loadLastSession] requires both keys to be present.
/// - [jobId] is persisted on every JobList row tap and is optional — the
///   cold-start path still works when it's null; only the "auto-push the
///   SpecReader" niceness in M1d depends on it.
///
/// Cleared on sign-out via [clearLastSession].
class LastSession {
  const LastSession({required this.repo, required this.workdir, this.jobId});

  final RepoRef repo;
  final String workdir;

  /// `Job.jobId` of the last-opened job (e.g. `spec-foo-123`) or `null`
  /// when no job has been opened in this session yet.
  final String? jobId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LastSession &&
          other.repo == repo &&
          other.workdir == workdir &&
          other.jobId == jobId;

  @override
  int get hashCode => Object.hash(repo, workdir, jobId);

  @override
  String toString() =>
      'LastSession(repo: $repo, workdir: $workdir, jobId: $jobId)';
}

/// Internal codec for [RepoRef] persisted in [SecureStoragePort]. Format:
/// `"<owner>|<name>|<defaultBranch>"` where literal `|` in any field is
/// percent-encoded as `%7C` (and literal `%` as `%25`) so pipes
/// unambiguously separate the three fields. Mirrors the
/// [AuthIdentityCodec] convention already in use for [GitIdentity].
class LastSessionRepoCodec {
  const LastSessionRepoCodec._();

  static String encode(RepoRef ref) =>
      '${_escape(ref.owner)}|${_escape(ref.name)}|${_escape(ref.defaultBranch)}';

  /// Returns `null` for blobs that don't match the
  /// `owner|name|defaultBranch` shape.
  static RepoRef? decode(String blob) {
    final parts = blob.split('|');
    if (parts.length != 3) return null;
    final owner = _unescape(parts[0]);
    final name = _unescape(parts[1]);
    final branch = _unescape(parts[2]);
    if (owner.isEmpty || name.isEmpty || branch.isEmpty) return null;
    return RepoRef(owner: owner, name: name, defaultBranch: branch);
  }

  static String _escape(String s) =>
      s.replaceAll('%', '%25').replaceAll('|', '%7C');
  static String _unescape(String s) =>
      s.replaceAll('%7C', '|').replaceAll('%25', '%');
}

/// Reads the three `SecureStorageKeys.lastOpened*` keys and returns a
/// [LastSession] when both repo + workdir are present, else `null`. A
/// malformed repo blob (shouldn't happen — we wrote it) is treated as
/// missing so the UI falls back to the RepoPicker rather than crashing.
///
/// Called once at bootstrap before `runApp`; must not throw — any storage
/// failure is logged and `null` is returned so cold-start still proceeds
/// to the RepoPicker.
Future<LastSession?> loadLastSession(SecureStoragePort storage) async {
  try {
    final repoBlob = await storage.readString(SecureStorageKeys.lastOpenedRepo);
    final workdir =
        await storage.readString(SecureStorageKeys.lastOpenedWorkdir);
    if (repoBlob == null || workdir == null) return null;
    final repo = LastSessionRepoCodec.decode(repoBlob);
    if (repo == null) return null;
    final jobId =
        await storage.readString(SecureStorageKeys.lastOpenedJobId);
    return LastSession(repo: repo, workdir: workdir, jobId: jobId);
  } on SecureStorageException catch (e) {
    developer.log(
      'loadLastSession: storage read failed; proceeding without preload',
      name: 'gitmdscribe.last_session',
      error: e,
    );
    return null;
  }
}

/// Persists [repo] + [workdir] so the next cold start can skip
/// RepoPicker. Does not touch the [SecureStorageKeys.lastOpenedJobId] key
/// — callers persist that separately on a JobList tap via
/// [saveLastOpenedJobId] so we don't accidentally clobber a known jobId
/// when the user re-picks the same repo.
Future<void> saveLastOpenedRepo(
  SecureStoragePort storage, {
  required RepoRef repo,
  required String workdir,
}) async {
  await storage.writeString(
    SecureStorageKeys.lastOpenedRepo,
    LastSessionRepoCodec.encode(repo),
  );
  await storage.writeString(SecureStorageKeys.lastOpenedWorkdir, workdir);
}

/// Persists [jobId] independently of the repo/workdir pair. Passing
/// `null` clears the key — useful when deep-linking state changes imply
/// "no job is currently selected".
Future<void> saveLastOpenedJobId(
  SecureStoragePort storage,
  String? jobId,
) async {
  if (jobId == null) {
    await storage.delete(SecureStorageKeys.lastOpenedJobId);
    return;
  }
  await storage.writeString(SecureStorageKeys.lastOpenedJobId, jobId);
}

/// Removes all three `lastOpened*` keys. Called on sign-out so the next
/// launch lands on SignIn → RepoPicker rather than restoring a session
/// tied to a revoked token.
Future<void> clearLastSession(SecureStoragePort storage) async {
  await storage.delete(SecureStorageKeys.lastOpenedRepo);
  await storage.delete(SecureStorageKeys.lastOpenedWorkdir);
  await storage.delete(SecureStorageKeys.lastOpenedJobId);
}

/// Lightweight, in-SDK-only (`dart:developer`) timing recorder for the
/// NFR-2 cold-start budget. Three checkpoints:
///
///   1. [markPreload] — pre-`runApp`, immediately after
///      [loadLastSession] returns. Captures the time spent rehydrating.
///   2. [markFirstFrame] — wired from
///      `WidgetsBinding.instance.addPostFrameCallback` in `_App.build`
///      so the first real frame with content registers.
///   3. [markJobListVisible] — fired by a provider listener the moment
///      the JobList controller lands in a `JobListLoaded` state.
///
/// Each `mark*` call logs to `developer.log` under the
/// `gitmdscribe.nfr2` name, tagged with the delta since the previous
/// checkpoint, so `adb logcat | grep nfr2` on-device reports the full
/// budget breakdown.
///
/// Deliberately does not use `package:flutter/…` — we want this usable
/// from `main()` before `WidgetsFlutterBinding.ensureInitialized()`
/// finishes and from tests without any Flutter plumbing.
class ColdStartTracker {
  ColdStartTracker({DateTime? start}) : _start = start ?? DateTime.now();

  final DateTime _start;
  DateTime? _preload;
  DateTime? _firstFrame;
  DateTime? _jobListVisible;

  /// Timestamp when the tracker was constructed. Callers treat this as
  /// `main()` entry.
  DateTime get start => _start;

  /// Timestamp of [markPreload], or `null` if not yet called.
  DateTime? get preload => _preload;

  /// Timestamp of [markFirstFrame], or `null` if not yet called.
  DateTime? get firstFrame => _firstFrame;

  /// Timestamp of [markJobListVisible], or `null` if not yet called.
  DateTime? get jobListVisible => _jobListVisible;

  /// Records "preload done — about to `runApp`". Safe to call multiple
  /// times; only the first invocation is recorded.
  void markPreload() {
    if (_preload != null) return;
    _preload = DateTime.now();
    _log('preload', _preload!.difference(_start));
  }

  /// Records "first Flutter frame painted". Wire from
  /// `WidgetsBinding.instance.addPostFrameCallback`. Safe to call
  /// multiple times; only the first invocation is recorded.
  void markFirstFrame() {
    if (_firstFrame != null) return;
    _firstFrame = DateTime.now();
    _log('first-frame', _firstFrame!.difference(_start));
  }

  /// Records "JobList reached a Loaded state". Wire from a provider
  /// listener on `jobListControllerProvider`. Safe to call multiple
  /// times; only the first invocation is recorded.
  void markJobListVisible() {
    if (_jobListVisible != null) return;
    _jobListVisible = DateTime.now();
    _log('job-list-visible', _jobListVisible!.difference(_start));
  }

  void _log(String phase, Duration delta) {
    developer.log(
      '$phase +${delta.inMilliseconds}ms',
      name: 'gitmdscribe.nfr2',
    );
  }
}
