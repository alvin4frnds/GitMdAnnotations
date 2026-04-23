import 'package:flutter_test/flutter_test.dart';
import 'package:gitmdscribe/domain/fakes/fake_file_system.dart';
import 'package:gitmdscribe/domain/ports/file_system_port.dart';

void main() {
  group('FakeFileSystem', () {
    late FakeFileSystem fs;

    setUp(() {
      fs = FakeFileSystem();
    });

    test('writeString then readString round-trips UTF-8 contents', () async {
      await fs.writeString('/a/b/c.txt', 'hello world');
      expect(await fs.readString('/a/b/c.txt'), 'hello world');
    });

    test('writeBytes then readBytes round-trips bytes', () async {
      final bytes = [0, 1, 2, 3, 250, 251, 252];
      await fs.writeBytes('/a/b/c.bin', bytes);
      expect(await fs.readBytes('/a/b/c.bin'), bytes);
    });

    test('readString on missing path throws FsNotFound', () async {
      await expectLater(
        fs.readString('/missing.txt'),
        throwsA(
          isA<FsNotFound>().having((e) => e.path, 'path', '/missing.txt'),
        ),
      );
    });

    test('readBytes on missing path throws FsNotFound', () async {
      await expectLater(
        fs.readBytes('/missing.bin'),
        throwsA(isA<FsNotFound>()),
      );
    });

    test('readString on a directory throws FsNotAFile', () async {
      await fs.mkdirp('/a/b');
      await expectLater(
        fs.readString('/a/b'),
        throwsA(isA<FsNotAFile>().having((e) => e.path, 'path', '/a/b')),
      );
    });

    test('readBytes on a directory throws FsNotAFile', () async {
      await fs.mkdirp('/a/b');
      await expectLater(
        fs.readBytes('/a/b'),
        throwsA(isA<FsNotAFile>()),
      );
    });

    test('listDir on missing dir throws FsNotFound', () async {
      await expectLater(
        fs.listDir('/nope'),
        throwsA(isA<FsNotFound>().having((e) => e.path, 'path', '/nope')),
      );
    });

    test('listDir on a file throws FsNotADirectory', () async {
      await fs.writeString('/a.txt', 'x');
      await expectLater(
        fs.listDir('/a.txt'),
        throwsA(
          isA<FsNotADirectory>().having((e) => e.path, 'path', '/a.txt'),
        ),
      );
    });

    test('listDir returns only immediate children with correct isDirectory',
        () async {
      await fs.writeString('/root/a.txt', 'a');
      await fs.writeString('/root/sub/b.txt', 'b');
      await fs.mkdirp('/root/empty');

      final entries = await fs.listDir('/root');
      final byName = {for (final e in entries) e.name: e};

      expect(byName.keys, unorderedEquals(['a.txt', 'sub', 'empty']));
      expect(byName['a.txt']!.isDirectory, isFalse);
      expect(byName['a.txt']!.path, '/root/a.txt');
      expect(byName['sub']!.isDirectory, isTrue);
      expect(byName['sub']!.path, '/root/sub');
      expect(byName['empty']!.isDirectory, isTrue);
    });

    test('listDir does not include grandchildren', () async {
      await fs.writeString('/root/sub/deep/x.txt', 'x');
      final entries = await fs.listDir('/root');
      expect(entries.map((e) => e.name), ['sub']);
    });

    test('mkdirp creates all intermediate directories', () async {
      await fs.mkdirp('/a/b/c/d');
      expect(await fs.exists('/a'), isTrue);
      expect(await fs.exists('/a/b'), isTrue);
      expect(await fs.exists('/a/b/c'), isTrue);
      expect(await fs.exists('/a/b/c/d'), isTrue);
      final entries = await fs.listDir('/a/b/c');
      expect(entries.single.name, 'd');
      expect(entries.single.isDirectory, isTrue);
    });

    test('mkdirp is a no-op if already a directory', () async {
      await fs.mkdirp('/x/y');
      await expectLater(fs.mkdirp('/x/y'), completes);
    });

    test('mkdirp at an existing file path throws FsNotADirectory', () async {
      await fs.writeString('/file.txt', 'hello');
      await expectLater(
        fs.mkdirp('/file.txt'),
        throwsA(
          isA<FsNotADirectory>().having((e) => e.path, 'path', '/file.txt'),
        ),
      );
    });

    test('remove on a directory deletes it and all descendants', () async {
      await fs.writeString('/tree/a.txt', 'a');
      await fs.writeString('/tree/sub/b.txt', 'b');
      await fs.writeString('/tree/sub/deep/c.txt', 'c');
      await fs.mkdirp('/tree/empty');

      await fs.remove('/tree');

      expect(await fs.exists('/tree'), isFalse);
      expect(await fs.exists('/tree/a.txt'), isFalse);
      expect(await fs.exists('/tree/sub'), isFalse);
      expect(await fs.exists('/tree/sub/b.txt'), isFalse);
      expect(await fs.exists('/tree/sub/deep/c.txt'), isFalse);
      expect(await fs.exists('/tree/empty'), isFalse);
    });

    test('remove on a missing path is a no-op', () async {
      await expectLater(fs.remove('/nope'), completes);
    });

    test('remove on a single file deletes only that file', () async {
      await fs.writeString('/a/x.txt', 'x');
      await fs.writeString('/a/y.txt', 'y');
      await fs.remove('/a/x.txt');
      expect(await fs.exists('/a/x.txt'), isFalse);
      expect(await fs.exists('/a/y.txt'), isTrue);
      expect(await fs.exists('/a'), isTrue);
    });

    test('exists returns true for files and directories', () async {
      await fs.writeString('/file.txt', 'x');
      await fs.mkdirp('/dir');
      expect(await fs.exists('/file.txt'), isTrue);
      expect(await fs.exists('/dir'), isTrue);
      expect(await fs.exists('/missing'), isFalse);
    });

    test('appDocsPath uses the configured appDocsRoot', () async {
      final custom = FakeFileSystem(appDocsRoot: '/my/docs');
      expect(await custom.appDocsPath('notes.txt'), '/my/docs/notes.txt');
      expect(await custom.appDocsPath('sub/file.txt'),
          '/my/docs/sub/file.txt');
    });

    test('appDocsPath defaults to /docs', () async {
      expect(await fs.appDocsPath('a.txt'), '/docs/a.txt');
    });

    test('writeString creates parent dirs automatically', () async {
      await fs.writeString('/deep/path/a.txt', 'hi');
      expect(await fs.exists('/deep'), isTrue);
      expect(await fs.exists('/deep/path'), isTrue);
      final entries = await fs.listDir('/deep/path');
      expect(entries.single.name, 'a.txt');
      expect(entries.single.isDirectory, isFalse);
    });

    test('writeString overwrites an existing file', () async {
      await fs.writeString('/a.txt', 'first');
      await fs.writeString('/a.txt', 'second');
      expect(await fs.readString('/a.txt'), 'second');
    });

    test('seedFile creates parent dirs and writes contents', () async {
      fs.seedFile('/seeded/hello.txt', 'seed');
      expect(await fs.readString('/seeded/hello.txt'), 'seed');
      expect(await fs.exists('/seeded'), isTrue);
    });

    test('trailing slash on a directory path is tolerated', () async {
      await fs.mkdirp('/a/b/');
      expect(await fs.exists('/a/b'), isTrue);
      expect(await fs.exists('/a/b/'), isTrue);
    });
  });
}
