import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../domain/ports/file_system_port.dart';

/// Production [FileSystemPort] backed by `dart:io`. Translates
/// `PathNotFoundException` -> [FsNotFound] and `FileSystemException`
/// -> [FsIoFailure] so the domain layer never sees a raw platform error.
///
/// Uses [getApplicationDocumentsDirectory] from `package:path_provider`
/// for [appDocsPath]. No caching; each call hits the real filesystem.
class FsAdapter implements FileSystemPort {
  FsAdapter();

  @override
  Future<bool> exists(String path) async {
    final type = await FileSystemEntity.type(path);
    return type != FileSystemEntityType.notFound;
  }

  @override
  Future<List<FsEntry>> listDir(String dir) async {
    final type = await FileSystemEntity.type(dir);
    if (type == FileSystemEntityType.notFound) throw FsNotFound(dir);
    if (type != FileSystemEntityType.directory) throw FsNotADirectory(dir);
    try {
      final d = Directory(dir);
      final entries = <FsEntry>[];
      await for (final child in d.list(followLinks: false)) {
        final stat = await child.stat();
        entries.add(FsEntry(
          path: child.path,
          name: _basename(child.path),
          isDirectory: stat.type == FileSystemEntityType.directory,
        ));
      }
      return entries;
    } on PathNotFoundException {
      throw FsNotFound(dir);
    } on FileSystemException catch (e) {
      throw FsIoFailure(dir, e);
    }
  }

  @override
  Future<String> readString(String path) async {
    await _assertReadableFile(path);
    try {
      return await File(path).readAsString();
    } on PathNotFoundException {
      throw FsNotFound(path);
    } on FileSystemException catch (e) {
      throw FsIoFailure(path, e);
    }
  }

  @override
  Future<List<int>> readBytes(String path) async {
    await _assertReadableFile(path);
    try {
      return await File(path).readAsBytes();
    } on PathNotFoundException {
      throw FsNotFound(path);
    } on FileSystemException catch (e) {
      throw FsIoFailure(path, e);
    }
  }

  @override
  Future<void> writeString(String path, String contents) async {
    await _ensureParentDir(path);
    try {
      await File(path).writeAsString(contents, flush: false, encoding: utf8);
    } on FileSystemException catch (e) {
      throw FsIoFailure(path, e);
    }
  }

  @override
  Future<void> writeBytes(String path, List<int> bytes) async {
    await _ensureParentDir(path);
    try {
      await File(path).writeAsBytes(bytes, flush: false);
    } on FileSystemException catch (e) {
      throw FsIoFailure(path, e);
    }
  }

  @override
  Future<void> mkdirp(String path) async {
    final type = await FileSystemEntity.type(path);
    if (type == FileSystemEntityType.file ||
        type == FileSystemEntityType.link) {
      throw FsNotADirectory(path);
    }
    try {
      await Directory(path).create(recursive: true);
    } on FileSystemException catch (e) {
      throw FsIoFailure(path, e);
    }
  }

  @override
  Future<void> remove(String path) async {
    final type = await FileSystemEntity.type(path);
    if (type == FileSystemEntityType.notFound) return;
    try {
      if (type == FileSystemEntityType.directory) {
        await Directory(path).delete(recursive: true);
      } else {
        await File(path).delete();
      }
    } on PathNotFoundException {
      return;
    } on FileSystemException catch (e) {
      throw FsIoFailure(path, e);
    }
  }

  @override
  Future<String> appDocsPath(String sub) async {
    final dir = await getApplicationDocumentsDirectory();
    final sep = Platform.pathSeparator;
    final base = dir.path.endsWith(sep)
        ? dir.path.substring(0, dir.path.length - 1)
        : dir.path;
    final tail =
        sub.startsWith('/') || sub.startsWith(sep) ? sub.substring(1) : sub;
    return '$base$sep$tail';
  }

  Future<void> _assertReadableFile(String path) async {
    final type = await FileSystemEntity.type(path);
    if (type == FileSystemEntityType.notFound) throw FsNotFound(path);
    if (type == FileSystemEntityType.directory) throw FsNotAFile(path);
  }

  Future<void> _ensureParentDir(String path) async {
    final parent = File(path).parent;
    if (!await parent.exists()) await parent.create(recursive: true);
  }

  String _basename(String path) {
    final slash = path.lastIndexOf(RegExp(r'[\\/]'));
    return slash < 0 ? path : path.substring(slash + 1);
  }
}
