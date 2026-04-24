import 'package:flutter_test/flutter_test.dart';
import 'package:gitmdscribe/domain/fakes/fake_file_system.dart';
import 'package:gitmdscribe/domain/services/mermaid_cache.dart';

void main() {
  group('MermaidCache.keyFor', () {
    test('same source -> same key', () {
      expect(
        MermaidCache.keyFor('graph TD\nA-->B'),
        MermaidCache.keyFor('graph TD\nA-->B'),
      );
    });

    test('whitespace differences are part of the key', () {
      final a = MermaidCache.keyFor('graph TD\nA-->B');
      final b = MermaidCache.keyFor('graph TD\n A-->B');
      expect(a, isNot(b));
    });

    test('key is a 64-hex SHA-256 digest', () {
      final k = MermaidCache.keyFor('whatever');
      expect(k, matches(RegExp(r'^[0-9a-f]{64}$')));
    });
  });

  group('MermaidCache.read/write', () {
    test('miss then hit: second call returns the written svg', () async {
      final fs = FakeFileSystem();
      final cache = MermaidCache(fs: fs);
      const source = 'graph TD\nA-->B';
      expect(await cache.read(source), isNull);

      await cache.write(source, '<svg>cached</svg>');
      expect(await cache.read(source), '<svg>cached</svg>');
    });

    test('write for one source does not match a different source',
        () async {
      final fs = FakeFileSystem();
      final cache = MermaidCache(fs: fs);
      await cache.write('source-a', '<svg>a</svg>');
      expect(await cache.read('source-b'), isNull);
    });

    test('cache path is under appDocs/mermaid-cache/<sha>.svg', () async {
      final fs = FakeFileSystem(appDocsRoot: '/docs');
      final cache = MermaidCache(fs: fs);
      const source = 'graph TD\nA-->B';
      await cache.write(source, '<svg/>');

      final expectedKey = MermaidCache.keyFor(source);
      final expectedPath = '/docs/mermaid-cache/$expectedKey.svg';
      expect(await fs.exists(expectedPath), isTrue);
      expect(await fs.readString(expectedPath), '<svg/>');
    });
  });
}
