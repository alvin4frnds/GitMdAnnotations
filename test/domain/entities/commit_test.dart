import 'package:flutter_test/flutter_test.dart';
import 'package:gitmdscribe/domain/entities/commit.dart';
import 'package:gitmdscribe/domain/entities/git_identity.dart';

void main() {
  const id = GitIdentity(name: 'A', email: 'a@x');
  final ts = DateTime(2026, 4, 20, 9, 14, 22);

  group('Commit', () {
    test('constructs with sha, message, identity, timestamp, parents', () {
      final c = Commit(
        sha: 'a3f91c',
        message: 'review: spec-42',
        identity: id,
        timestamp: ts,
        parents: const ['p1', 'p2'],
      );
      expect(c.sha, 'a3f91c');
      expect(c.message, 'review: spec-42');
      expect(c.identity, id);
      expect(c.timestamp, ts);
      expect(c.parents, ['p1', 'p2']);
    });

    test('equal fields produce equal commits', () {
      final a = Commit(
        sha: 'a',
        message: 'm',
        identity: id,
        timestamp: ts,
        parents: const ['p1'],
      );
      final b = Commit(
        sha: 'a',
        message: 'm',
        identity: id,
        timestamp: ts,
        parents: const ['p1'],
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('different sha is unequal', () {
      final a = Commit(
        sha: 'a',
        message: 'm',
        identity: id,
        timestamp: ts,
        parents: const [],
      );
      final b = Commit(
        sha: 'b',
        message: 'm',
        identity: id,
        timestamp: ts,
        parents: const [],
      );
      expect(a, isNot(equals(b)));
    });

    test('different parents list is unequal', () {
      final a = Commit(
        sha: 's',
        message: 'm',
        identity: id,
        timestamp: ts,
        parents: const ['p1'],
      );
      final b = Commit(
        sha: 's',
        message: 'm',
        identity: id,
        timestamp: ts,
        parents: const ['p2'],
      );
      expect(a, isNot(equals(b)));
    });

    test('toString includes sha and message', () {
      final c = Commit(
        sha: 'a3f91c',
        message: 'review: spec-42',
        identity: id,
        timestamp: ts,
        parents: const [],
      );
      final s = c.toString();
      expect(s, contains('a3f91c'));
      expect(s, contains('review: spec-42'));
    });
  });
}
