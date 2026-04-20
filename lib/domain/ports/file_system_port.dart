/// Abstract boundary between the domain and any platform filesystem.
///
/// Domain-layer code (spec module §4.3, review module §4.7) talks to this
/// port so that `lib/domain/**` stays Flutter-free and libgit2/dart:io are
/// confined to `lib/infra/fs/`. Tests drive the [FakeFileSystem] in
/// `lib/domain/fakes/`; production wires [FileSystemPort] to `FsAdapter`.
///
/// Paths are POSIX-style (`/a/b/c`). Adapters carry their own notion of a
/// root; the fake keeps a single virtual root at `/`.
abstract class FileSystemPort {
  /// Returns true if [path] exists (file OR directory).
  Future<bool> exists(String path);

  /// Lists immediate (non-recursive) children of [dir]. Throws [FsNotFound]
  /// if [dir] doesn't exist, [FsNotADirectory] if it exists but is a file.
  Future<List<FsEntry>> listDir(String dir);

  /// Reads the full UTF-8 contents of [path]. Throws [FsNotFound] or
  /// [FsNotAFile] as appropriate.
  Future<String> readString(String path);

  /// Reads the full bytes of [path]. Same error semantics as [readString].
  Future<List<int>> readBytes(String path);

  /// Writes [contents] (UTF-8) to [path], creating parent dirs as needed.
  /// Overwrites any existing file.
  Future<void> writeString(String path, String contents);

  /// Writes [bytes] to [path], creating parent dirs. Overwrites.
  Future<void> writeBytes(String path, List<int> bytes);

  /// Creates a directory (recursively). No-op if already a directory.
  /// Throws [FsNotADirectory] if a non-directory exists at [path].
  Future<void> mkdirp(String path);

  /// Removes [path]; if a directory, removes recursively. No-op if missing.
  Future<void> remove(String path);

  /// Returns a writable absolute path inside the app's documents directory
  /// with [sub] appended. Adapters resolve this against the platform's app
  /// docs dir; the fake returns `'$appDocsRoot/$sub'`.
  Future<String> appDocsPath(String sub);
}

/// Immediate child of a directory returned from [FileSystemPort.listDir].
class FsEntry {
  const FsEntry({
    required this.path,
    required this.name,
    required this.isDirectory,
  });

  /// Absolute path in the port's root namespace.
  final String path;

  /// Basename only (no slashes).
  final String name;

  final bool isDirectory;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FsEntry &&
          other.path == path &&
          other.name == name &&
          other.isDirectory == isDirectory;

  @override
  int get hashCode => Object.hash(path, name, isDirectory);

  @override
  String toString() =>
      'FsEntry(path: $path, name: $name, isDir: $isDirectory)';
}

/// Sealed root of every error a [FileSystemPort] is allowed to throw.
/// Callers pattern-match on concrete subtypes; adapters translate raw
/// platform exceptions into these so the domain never sees them.
sealed class FsError implements Exception {
  const FsError();
}

class FsNotFound extends FsError {
  const FsNotFound(this.path);
  final String path;

  @override
  String toString() => 'FsNotFound($path)';
}

class FsNotAFile extends FsError {
  const FsNotAFile(this.path);
  final String path;

  @override
  String toString() => 'FsNotAFile($path)';
}

class FsNotADirectory extends FsError {
  const FsNotADirectory(this.path);
  final String path;

  @override
  String toString() => 'FsNotADirectory($path)';
}

class FsIoFailure extends FsError {
  const FsIoFailure(this.path, this.cause);
  final String path;
  final Object cause;

  @override
  String toString() => 'FsIoFailure($path, cause: $cause)';
}
