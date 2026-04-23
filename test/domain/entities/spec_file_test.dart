import 'package:flutter_test/flutter_test.dart';
import 'package:gitmdscribe/domain/entities/source_kind.dart';
import 'package:gitmdscribe/domain/entities/spec_file.dart';

void main() {
  group('SpecFile', () {
    test('constructs with path, sha, contents, and sourceKind', () {
      final f = SpecFile(
        path: 'jobs/pending/spec-a/02-spec.md',
        sha: 'a3f91c',
        contents: '# Hello',
        sourceKind: SourceKind.markdown,
      );
      expect(f.path, 'jobs/pending/spec-a/02-spec.md');
      expect(f.sha, 'a3f91c');
      expect(f.contents, '# Hello');
      expect(f.sourceKind, SourceKind.markdown);
    });

    test('equal fields produce equal instances', () {
      final a = SpecFile(
        path: 'p',
        sha: 's',
        contents: 'c',
        sourceKind: SourceKind.markdown,
      );
      final b = SpecFile(
        path: 'p',
        sha: 's',
        contents: 'c',
        sourceKind: SourceKind.markdown,
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('different sha makes instances unequal', () {
      final a = SpecFile(
        path: 'p',
        sha: 's1',
        contents: 'c',
        sourceKind: SourceKind.markdown,
      );
      final b = SpecFile(
        path: 'p',
        sha: 's2',
        contents: 'c',
        sourceKind: SourceKind.markdown,
      );
      expect(a, isNot(equals(b)));
    });

    test('toString includes path and sha but not contents', () {
      final f = SpecFile(
        path: 'p',
        sha: 'abc',
        contents: 'secret content',
        sourceKind: SourceKind.markdown,
      );
      final s = f.toString();
      expect(s, contains('p'));
      expect(s, contains('abc'));
      expect(s, isNot(contains('secret content')));
    });

    test('throws ArgumentError on empty sha', () {
      expect(
        () => SpecFile(
          path: 'p',
          sha: '',
          contents: 'c',
          sourceKind: SourceKind.markdown,
        ),
        throwsArgumentError,
      );
    });
  });
}
