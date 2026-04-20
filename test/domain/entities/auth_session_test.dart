import 'package:flutter_test/flutter_test.dart';
import 'package:gitmdannotations_tablet/domain/entities/auth_session.dart';
import 'package:gitmdannotations_tablet/domain/entities/git_identity.dart';

void main() {
  group('AuthSession', () {
    const id = GitIdentity(name: 'A', email: 'a@x');

    test('constructs with token and identity', () {
      const s = AuthSession(token: 'ghp_abc', identity: id);
      expect(s.token, 'ghp_abc');
      expect(s.identity, id);
    });

    test('equal fields produce equal instances', () {
      const a = AuthSession(token: 't', identity: id);
      const b = AuthSession(token: 't', identity: id);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('different token makes sessions unequal', () {
      const a = AuthSession(token: 't1', identity: id);
      const b = AuthSession(token: 't2', identity: id);
      expect(a, isNot(equals(b)));
    });

    test('toString redacts the token', () {
      const s = AuthSession(token: 'ghp_super_secret', identity: id);
      expect(s.toString(), isNot(contains('ghp_super_secret')));
      expect(s.toString(), contains('A'));
    });
  });
}
