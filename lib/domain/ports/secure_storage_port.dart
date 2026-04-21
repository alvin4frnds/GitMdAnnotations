/// Abstract boundary between the domain and the platform-backed secure
/// key-value store (Android Keystore via `flutter_secure_storage` in
/// production, an in-memory map in tests).
///
/// See IMPLEMENTATION.md §2.1 (layer/port/adapter rule), §4.1 FR-3–5, and
/// TabletApp-PRD.md §5.10.3 for the requirement to back auth token + git
/// identity with the Android Keystore.
abstract class SecureStoragePort {
  /// Writes [value] at [key], overwriting any existing value.
  Future<void> writeString(String key, String value);

  /// Returns the value stored at [key], or `null` if the key is absent.
  Future<String?> readString(String key);

  /// Removes [key]. Implementations must be no-ops when the key is absent.
  Future<void> delete(String key);

  /// Returns whether [key] is currently present in the store.
  Future<bool> containsKey(String key);

  /// Removes every entry this port owns.
  Future<void> clear();
}

/// Stable keys used by the `auth` module. Kept minimal (YAGNI): we only
/// add a constant here once the corresponding feature actually exists.
class SecureStorageKeys {
  const SecureStorageKeys._();

  /// GitHub access token (OAuth Device Flow or PAT).
  static const authToken = 'auth.token.v1';

  /// JSON-serialized [GitIdentity] (`name`, `email`).
  static const gitIdentity = 'auth.git_identity.v1';

  // -- last-session / NFR-2 cold-start preload --

  /// Encoded [RepoRef] of the most-recently picked repo. Format is
  /// `"<owner>|<name>|<defaultBranch>"` (pipes escaped) — see
  /// `lib/app/last_session.dart`. Restored at bootstrap so RepoPicker
  /// doesn't block the first frame on a `GET /user/repos`.
  static const lastOpenedRepo = 'session.last_repo.v1';

  /// Absolute local workdir path that [lastOpenedRepo] was cloned into.
  /// Paired with [lastOpenedRepo] — rehydrating one without the other is
  /// a no-op.
  static const lastOpenedWorkdir = 'session.last_workdir.v1';

  /// `Job.jobId` (e.g. `spec-foo-123`) of the job the user was last
  /// viewing. Optional — the cold-start flow still works when this is
  /// absent; the M1d "resume where you left off" push uses it when set.
  static const lastOpenedJobId = 'session.last_job_id.v1';
}

/// Typed error raised by [SecureStoragePort] adapters when the underlying
/// platform throws. Domain callers catch this instead of `PlatformException`
/// so that `lib/domain/**` stays Flutter-free.
class SecureStorageException implements Exception {
  const SecureStorageException(this.message, {this.cause});

  /// Human-readable description of what went wrong.
  final String message;

  /// Optional underlying error preserved for logging / debugging.
  final Object? cause;

  @override
  String toString() {
    if (cause == null) return 'SecureStorageException: $message';
    return 'SecureStorageException: $message (cause: $cause)';
  }
}
