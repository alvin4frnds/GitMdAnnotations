import 'dart:io';

import 'package:flutter/services.dart' show MissingPluginException;
import 'package:flutter_test/flutter_test.dart';
import 'package:gitmdannotations_tablet/domain/ports/file_system_port.dart';
import 'package:gitmdannotations_tablet/infra/fs/fs_adapter.dart';

/// Minimal smoke test for [FsAdapter]. Heavier filesystem round-trips belong
/// in integration tests; here we just exercise the surface without requiring
/// a Flutter platform channel. `path_provider`-backed methods are skipped if
/// no binding is available (MissingPluginException).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FsAdapter', () {
    late FsAdapter adapter;

    setUp(() {
      adapter = FsAdapter();
    });

    test('is constructible without args and implements FileSystemPort', () {
      expect(adapter, isA<FileSystemPort>());
    });

    test('exists on a definitely-missing path returns false (no throw)',
        () async {
      final miss = '${Directory.systemTemp.path}/__gitmd_missing__'
          '_${DateTime.now().microsecondsSinceEpoch}';
      expect(await adapter.exists(miss), isFalse);
    });

    test('writeString + readString round-trip under a real tmp dir',
        () async {
      final tmp = await Directory.systemTemp.createTemp('gitmd_fs_adapter_');
      try {
        final path = '${tmp.path}${Platform.pathSeparator}hello.txt';
        await adapter.writeString(path, 'hi there');
        expect(await adapter.exists(path), isTrue);
        expect(await adapter.readString(path), 'hi there');
      } finally {
        if (await tmp.exists()) {
          await tmp.delete(recursive: true);
        }
      }
    });

    test('readString on missing path throws FsNotFound', () async {
      final miss = '${Directory.systemTemp.path}/__gitmd_missing_read__'
          '_${DateTime.now().microsecondsSinceEpoch}';
      await expectLater(
        adapter.readString(miss),
        throwsA(isA<FsNotFound>()),
      );
    });

    test('appDocsPath resolves via path_provider when available', () async {
      try {
        final p = await adapter.appDocsPath('sub/file.txt');
        expect(p, contains('sub'));
        expect(p, endsWith('file.txt'));
      } on MissingPluginException {
        markTestSkipped('path_provider plugin not wired in unit-test harness');
      } catch (e) {
        // path_provider throws a generic Exception on Windows unit tests
        // without a platform binding; treat it as skipped.
        if (e.toString().contains('MissingPluginException') ||
            e.toString().contains('path_provider')) {
          markTestSkipped('path_provider unavailable: $e');
        } else {
          rethrow;
        }
      }
    });
  });
}
