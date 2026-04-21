import 'dart:io';
import 'dart:typed_data';

import 'package:shared_storage/shared_storage.dart' as saf;

import '../../domain/ports/backup_export_port.dart';

/// Production [BackupExportPort] backed by Android's Storage Access
/// Framework via `package:shared_storage` (M1d-T2).
///
/// Flow:
///   1. Check that `sourcePath` exists and contains at least one
///      regular file. If not, short-circuit to [ExportNoBackupsFound]
///      without prompting the user — the picker would otherwise pop
///      only for the copy to find nothing to do.
///   2. Launch `ACTION_OPEN_DOCUMENT_TREE` via `openDocumentTree`. The
///      user picks a destination folder (Downloads, external SD card,
///      Drive sync folder, anything that implements a DocumentsProvider).
///      If they dismiss the picker, `openDocumentTree` returns `null`
///      and we surface [ExportUserCancelled].
///   3. Walk the source tree depth-first. For each sub-directory,
///      create a matching `DocumentFile` directory under the picked
///      tree; for each regular file, read bytes and call
///      `createFileAsBytes` with a best-guess MIME type.
///   4. Return [ExportSucceeded] with the number of regular files that
///      were actually written. Any platform error mid-copy aborts the
///      walk and surfaces as [ExportFailed] — partial output is left in
///      place (SAF doesn't give us a transactional copy primitive; the
///      user can re-export and de-dupe by hand).
///
/// Non-goals: this is not a general-purpose SAF file manager. It exists
/// to let users rescue archived conflict backups; the backup tree is
/// small (tens of kB at most) so we read each file fully into memory.
/// Streaming is left for a future revision if we ever export something
/// the size of a raster cache.
class SharedStorageBackupExportAdapter implements BackupExportPort {
  /// [openDocumentTreeOverride], [createDirectoryOverride] and
  /// [createFileOverride] are test seams — production wiring leaves
  /// them null so the adapter calls the real `shared_storage` APIs.
  /// The seams exist because `shared_storage` talks to a real Android
  /// activity/method-channel under the hood, which has no fake
  /// available on the host VM.
  SharedStorageBackupExportAdapter({
    Future<Uri?> Function()? openDocumentTreeOverride,
    Future<saf.DocumentFile?> Function(Uri parent, String displayName)?
        createDirectoryOverride,
    Future<saf.DocumentFile?> Function({
      required Uri parentUri,
      required String mimeType,
      required String displayName,
      required Uint8List bytes,
    })? createFileOverride,
  })  : _openDocumentTree = openDocumentTreeOverride ?? saf.openDocumentTree,
        _createDirectory = createDirectoryOverride ?? saf.createDirectory,
        _createFileAsBytes =
            createFileOverride ?? _defaultCreateFileAsBytes;

  final Future<Uri?> Function() _openDocumentTree;
  final Future<saf.DocumentFile?> Function(Uri parent, String displayName)
      _createDirectory;
  final Future<saf.DocumentFile?> Function({
    required Uri parentUri,
    required String mimeType,
    required String displayName,
    required Uint8List bytes,
  }) _createFileAsBytes;

  static Future<saf.DocumentFile?> _defaultCreateFileAsBytes({
    required Uri parentUri,
    required String mimeType,
    required String displayName,
    required Uint8List bytes,
  }) {
    return saf.createFileAsBytes(
      parentUri,
      mimeType: mimeType,
      displayName: displayName,
      bytes: bytes,
    );
  }

  @override
  Future<ExportOutcome> exportDirectory({required String sourcePath}) async {
    final source = Directory(sourcePath);
    if (!source.existsSync()) {
      return const ExportNoBackupsFound();
    }
    // An empty source (no regular files anywhere in the subtree) is
    // treated as "no backups found" — we don't want to pop the picker
    // just to copy zero bytes.
    if (!_hasAnyRegularFile(source)) {
      return const ExportNoBackupsFound();
    }

    final Uri? destRoot;
    try {
      destRoot = await _openDocumentTree();
    } on Object catch (e) {
      return ExportFailed('Could not open folder picker: $e');
    }
    if (destRoot == null) {
      return const ExportUserCancelled();
    }

    try {
      final count = await _copyTree(source, destRoot);
      return ExportSucceeded(count);
    } on _ExportAbort catch (e) {
      return ExportFailed(e.message);
    } on Object catch (e) {
      return ExportFailed('Export failed: $e');
    }
  }

  /// Recursively copies every regular file under [source] into the SAF
  /// tree rooted at [destUri], creating directories along the way.
  /// Returns the count of regular files that were copied successfully.
  Future<int> _copyTree(Directory source, Uri destUri) async {
    var count = 0;
    for (final entity in source.listSync(followLinks: false)) {
      final name = _basename(entity.path);
      if (entity is Directory) {
        final child = await _createDirectory(destUri, name);
        if (child == null) {
          throw _ExportAbort('Could not create sub-folder "$name" at '
              'destination.');
        }
        count += await _copyTree(entity, child.uri);
      } else if (entity is File) {
        final bytes = await entity.readAsBytes();
        final result = await _createFileAsBytes(
          parentUri: destUri,
          mimeType: _mimeFor(name),
          displayName: name,
          bytes: bytes,
        );
        if (result == null) {
          throw _ExportAbort('Could not write "$name" to destination.');
        }
        count++;
      }
      // Skip symlinks / other FileSystemEntity kinds — the backup tree
      // is produced by libgit2 + our own code, neither of which emits
      // symlinks on Android.
    }
    return count;
  }

  static bool _hasAnyRegularFile(Directory dir) {
    for (final e in dir.listSync(recursive: true, followLinks: false)) {
      if (e is File) return true;
    }
    return false;
  }
}

/// Internal control-flow marker — thrown by [_copyTree] on any partial
/// failure so the outer `try` in [exportDirectory] can translate it to
/// [ExportFailed] without wrapping it as `ExportFailed('Exception: …')`.
class _ExportAbort implements Exception {
  _ExportAbort(this.message);
  final String message;
  @override
  String toString() => 'ExportAbort($message)';
}

String _basename(String path) {
  final slash = path.lastIndexOf(RegExp(r'[\\/]'));
  return slash < 0 ? path : path.substring(slash + 1);
}

/// Very small MIME-type guess table, scoped to the file kinds the
/// backup tree actually contains (markdown, json, svg, txt). Anything
/// unrecognised falls back to `application/octet-stream`, which the
/// SAF-side provider will accept.
String _mimeFor(String name) {
  final dot = name.lastIndexOf('.');
  if (dot < 0 || dot == name.length - 1) return 'application/octet-stream';
  final ext = name.substring(dot + 1).toLowerCase();
  switch (ext) {
    case 'md':
    case 'markdown':
      return 'text/markdown';
    case 'txt':
    case 'log':
      return 'text/plain';
    case 'json':
      return 'application/json';
    case 'svg':
      return 'image/svg+xml';
    case 'png':
      return 'image/png';
    case 'pdf':
      return 'application/pdf';
    default:
      return 'application/octet-stream';
  }
}
