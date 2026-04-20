import 'dart:convert';

import '../ports/file_system_port.dart';

/// In-memory, POSIX-style implementation of [FileSystemPort] for domain
/// tests. Does zero real I/O. Paths are normalized (trailing slashes
/// collapsed). All seeded paths auto-create their parent directories.
///
/// Conventions mirror [FakeGitPort]: test-friendly ctor, no external deps,
/// exposed seams for seeding. Intentionally permissive: paths are treated
/// as opaque POSIX strings so domain code can use `/repo/jobs/...` without
/// caring about the host platform.
class FakeFileSystem implements FileSystemPort {
  FakeFileSystem({this.appDocsRoot = '/docs'}) {
    _dirs.add('/');
  }

  /// Root used by [appDocsPath]. Defaults to `/docs`.
  final String appDocsRoot;

  final Map<String, String> _stringFiles = {};
  final Map<String, List<int>> _byteFiles = {};
  final Set<String> _dirs = {};

  // -- Test helpers ---------------------------------------------------------

  /// Seed a file + its parent dirs in one call. Test-only convenience.
  void seedFile(String path, String contents) {
    final p = _norm(path);
    _ensureParents(p);
    _stringFiles[p] = contents;
    _byteFiles.remove(p);
  }

  // -- FileSystemPort -------------------------------------------------------

  @override
  Future<bool> exists(String path) async {
    final p = _norm(path);
    return _isFile(p) || _isDir(p);
  }

  @override
  Future<List<FsEntry>> listDir(String dir) async {
    final d = _norm(dir);
    if (_isFile(d)) throw FsNotADirectory(d);
    if (!_isDir(d)) throw FsNotFound(d);

    final prefix = d == '/' ? '/' : '$d/';
    final seen = <String, FsEntry>{};

    void considerChild(String fullPath, bool isDirectory) {
      if (!fullPath.startsWith(prefix) || fullPath == d) return;
      final rest = fullPath.substring(prefix.length);
      if (rest.isEmpty) return;
      final slash = rest.indexOf('/');
      final name = slash < 0 ? rest : rest.substring(0, slash);
      final childPath = '$prefix$name';
      // A deeper path promotes the immediate child to a directory.
      final childIsDir = slash >= 0 ? true : isDirectory;
      final existing = seen[name];
      if (existing == null || (childIsDir && !existing.isDirectory)) {
        seen[name] = FsEntry(
          path: childPath,
          name: name,
          isDirectory: childIsDir,
        );
      }
    }

    for (final p in _stringFiles.keys) {
      considerChild(p, false);
    }
    for (final p in _byteFiles.keys) {
      considerChild(p, false);
    }
    for (final p in _dirs) {
      considerChild(p, true);
    }

    return seen.values.toList(growable: false);
  }

  @override
  Future<String> readString(String path) async {
    final p = _norm(path);
    if (_isDir(p)) throw FsNotAFile(p);
    final hit = _stringFiles[p];
    if (hit != null) return hit;
    final bytes = _byteFiles[p];
    if (bytes != null) return utf8.decode(bytes);
    throw FsNotFound(p);
  }

  @override
  Future<List<int>> readBytes(String path) async {
    final p = _norm(path);
    if (_isDir(p)) throw FsNotAFile(p);
    final bytes = _byteFiles[p];
    if (bytes != null) return List<int>.unmodifiable(bytes);
    final str = _stringFiles[p];
    if (str != null) return utf8.encode(str);
    throw FsNotFound(p);
  }

  @override
  Future<void> writeString(String path, String contents) async {
    final p = _norm(path);
    if (_isDir(p)) throw FsNotAFile(p);
    _ensureParents(p);
    _byteFiles.remove(p);
    _stringFiles[p] = contents;
  }

  @override
  Future<void> writeBytes(String path, List<int> bytes) async {
    final p = _norm(path);
    if (_isDir(p)) throw FsNotAFile(p);
    _ensureParents(p);
    _stringFiles.remove(p);
    _byteFiles[p] = List<int>.unmodifiable(bytes);
  }

  @override
  Future<void> mkdirp(String path) async {
    final p = _norm(path);
    if (_isFile(p)) throw FsNotADirectory(p);
    _ensureDir(p);
  }

  @override
  Future<void> remove(String path) async {
    final p = _norm(path);
    if (_isFile(p)) {
      _stringFiles.remove(p);
      _byteFiles.remove(p);
      return;
    }
    if (!_isDir(p)) return; // no-op on missing
    final prefix = p == '/' ? '/' : '$p/';
    _stringFiles.removeWhere((k, _) => k == p || k.startsWith(prefix));
    _byteFiles.removeWhere((k, _) => k == p || k.startsWith(prefix));
    _dirs.removeWhere((k) => k == p || k.startsWith(prefix));
  }

  @override
  Future<String> appDocsPath(String sub) async {
    final trimmed = sub.startsWith('/') ? sub.substring(1) : sub;
    return '$appDocsRoot/$trimmed';
  }

  // -- Internals ------------------------------------------------------------

  /// Collapse `///` -> `/`, strip trailing `/` (except for root), ensure a
  /// leading `/`. Everything in this class works on the normalized form.
  String _norm(String path) {
    var p = path.replaceAll(RegExp(r'/+'), '/');
    if (!p.startsWith('/')) p = '/$p';
    if (p.length > 1 && p.endsWith('/')) p = p.substring(0, p.length - 1);
    return p;
  }

  bool _isFile(String p) =>
      _stringFiles.containsKey(p) || _byteFiles.containsKey(p);

  bool _isDir(String p) => _dirs.contains(p);

  void _ensureParents(String path) {
    final idx = path.lastIndexOf('/');
    if (idx <= 0) return; // parent is '/'
    _ensureDir(path.substring(0, idx));
  }

  void _ensureDir(String path) {
    if (path.isEmpty || path == '/') {
      _dirs.add('/');
      return;
    }
    final parts = path.split('/').where((s) => s.isNotEmpty).toList();
    final buf = StringBuffer();
    for (final part in parts) {
      buf.write('/');
      buf.write(part);
      _dirs.add(buf.toString());
    }
  }
}
