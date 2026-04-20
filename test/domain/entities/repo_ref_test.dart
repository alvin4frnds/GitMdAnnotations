import 'package:flutter_test/flutter_test.dart';
import 'package:gitmdannotations_tablet/domain/entities/repo_ref.dart';

void main() {
  group('RepoRef', () {
    test('constructs with owner, name, and explicit defaultBranch', () {
      const ref = RepoRef(
        owner: 'anthropic',
        name: 'claude',
        defaultBranch: 'trunk',
      );
      expect(ref.owner, 'anthropic');
      expect(ref.name, 'claude');
      expect(ref.defaultBranch, 'trunk');
    });

    test('defaultBranch defaults to "main"', () {
      const ref = RepoRef(owner: 'a', name: 'b');
      expect(ref.defaultBranch, 'main');
    });

    test('value equality: equal fields produce equal instances', () {
      const a = RepoRef(owner: 'o', name: 'n');
      const b = RepoRef(owner: 'o', name: 'n');
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('value equality: different fields are unequal', () {
      const a = RepoRef(owner: 'o', name: 'n');
      const b = RepoRef(owner: 'o', name: 'different');
      expect(a, isNot(equals(b)));
    });

    test('toString includes identifying fields', () {
      const ref = RepoRef(owner: 'o', name: 'n');
      final s = ref.toString();
      expect(s, contains('o'));
      expect(s, contains('n'));
    });
  });
}
