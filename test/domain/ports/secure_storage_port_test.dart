import 'package:flutter_test/flutter_test.dart';
import 'package:gitmdscribe/domain/fakes/fake_secure_storage.dart';
import 'package:gitmdscribe/domain/ports/secure_storage_port.dart';

void main() {
  group('SecureStorageKeys', () {
    test('exposes the two keys currently in use', () {
      expect(SecureStorageKeys.authToken, 'auth.token.v1');
      expect(SecureStorageKeys.gitIdentity, 'auth.git_identity.v1');
    });
  });

  group('SecureStoragePort contract (via FakeSecureStorage)', () {
    late SecureStoragePort storage;

    setUp(() {
      storage = FakeSecureStorage();
    });

    test('writeString then readString returns the same value', () async {
      await storage.writeString('k', 'v');
      expect(await storage.readString('k'), 'v');
    });

    test('readString for a missing key returns null', () async {
      expect(await storage.readString('missing'), isNull);
    });

    test('delete removes a key (containsKey false, readString null)',
        () async {
      await storage.writeString('k', 'v');
      await storage.delete('k');
      expect(await storage.containsKey('k'), isFalse);
      expect(await storage.readString('k'), isNull);
    });

    test('delete on a missing key does not throw', () async {
      await expectLater(storage.delete('absent'), completes);
    });

    test('containsKey reflects state', () async {
      expect(await storage.containsKey('k'), isFalse);
      await storage.writeString('k', 'v');
      expect(await storage.containsKey('k'), isTrue);
      await storage.delete('k');
      expect(await storage.containsKey('k'), isFalse);
    });

    test('clear empties everything', () async {
      await storage.writeString('a', '1');
      await storage.writeString('b', '2');
      await storage.clear();
      expect(await storage.containsKey('a'), isFalse);
      expect(await storage.containsKey('b'), isFalse);
      expect(await storage.readString('a'), isNull);
    });

    test('overwriting an existing key updates the value', () async {
      await storage.writeString('k', 'first');
      await storage.writeString('k', 'second');
      expect(await storage.readString('k'), 'second');
    });

    test('round-trips multi-byte UTF-8 (emoji, non-ASCII) losslessly',
        () async {
      const payload = 'Zoë — 日本語 — rocket 🚀 — naïve';
      await storage.writeString(SecureStorageKeys.gitIdentity, payload);
      expect(
        await storage.readString(SecureStorageKeys.gitIdentity),
        payload,
      );
    });
  });

  group('SecureStorageException', () {
    test('carries a message and implements Exception', () {
      const err = SecureStorageException('boom');
      expect(err, isA<Exception>());
      expect(err.message, 'boom');
      expect(err.toString(), contains('boom'));
    });

    test('optional cause is preserved', () {
      final cause = StateError('underlying');
      final err = SecureStorageException('failed', cause: cause);
      expect(err.cause, cause);
      expect(err.toString(), contains('failed'));
    });
  });
}
