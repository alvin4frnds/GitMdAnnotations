import 'package:flutter_test/flutter_test.dart';
import 'package:gitmdannotations_tablet/domain/entities/git_identity.dart';

void main() {
  group('GitIdentity', () {
    test('constructs with name and email', () {
      const id = GitIdentity(name: 'Ada Lovelace', email: 'ada@example.com');
      expect(id.name, 'Ada Lovelace');
      expect(id.email, 'ada@example.com');
    });

    test('equal fields produce equal instances', () {
      const a = GitIdentity(name: 'A', email: 'a@x');
      const b = GitIdentity(name: 'A', email: 'a@x');
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('different email makes instances unequal', () {
      const a = GitIdentity(name: 'A', email: 'a@x');
      const b = GitIdentity(name: 'A', email: 'a@y');
      expect(a, isNot(equals(b)));
    });

    test('toString includes name and email', () {
      const id = GitIdentity(name: 'Ada', email: 'ada@x');
      final s = id.toString();
      expect(s, contains('Ada'));
      expect(s, contains('ada@x'));
    });
  });
}
