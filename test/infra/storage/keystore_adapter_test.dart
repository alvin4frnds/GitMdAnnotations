import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitmdscribe/domain/ports/secure_storage_port.dart';
import 'package:gitmdscribe/infra/storage/keystore_adapter.dart';

/// Scripted in-memory [SecureBackend] used only by these unit tests. It
/// mirrors the subset of `FlutterSecureStorage` the adapter calls, plus a
/// switch to make any call throw a [PlatformException] so we can verify
/// error translation.
class _FakeSecureBackend implements SecureBackend {
  final Map<String, String> store = {};
  PlatformException? failure;

  void _maybeThrow() {
    final f = failure;
    if (f != null) throw f;
  }

  @override
  Future<void> write({required String key, required String value}) async {
    _maybeThrow();
    store[key] = value;
  }

  @override
  Future<String?> read({required String key}) async {
    _maybeThrow();
    return store[key];
  }

  @override
  Future<void> delete({required String key}) async {
    _maybeThrow();
    store.remove(key);
  }

  @override
  Future<bool> containsKey({required String key}) async {
    _maybeThrow();
    return store.containsKey(key);
  }

  @override
  Future<void> deleteAll() async {
    _maybeThrow();
    store.clear();
  }
}

void main() {
  group('KeystoreAdapter', () {
    late _FakeSecureBackend backend;
    late KeystoreAdapter adapter;

    setUp(() {
      backend = _FakeSecureBackend();
      adapter = KeystoreAdapter(backend: backend);
    });

    test('is constructible with no args (uses default backend)', () {
      expect(KeystoreAdapter(), isA<SecureStoragePort>());
    });

    test('writeString delegates to backend.write', () async {
      await adapter.writeString('k', 'v');
      expect(backend.store, {'k': 'v'});
    });

    test('readString delegates to backend.read and returns value', () async {
      backend.store['k'] = 'v';
      expect(await adapter.readString('k'), 'v');
    });

    test('readString returns null for missing key', () async {
      expect(await adapter.readString('missing'), isNull);
    });

    test('delete delegates and is a no-op when absent', () async {
      backend.store['k'] = 'v';
      await adapter.delete('k');
      expect(backend.store, isEmpty);
      await expectLater(adapter.delete('k'), completes);
    });

    test('containsKey delegates to backend', () async {
      backend.store['k'] = 'v';
      expect(await adapter.containsKey('k'), isTrue);
      expect(await adapter.containsKey('other'), isFalse);
    });

    test('clear delegates to backend.deleteAll', () async {
      backend.store
        ..['a'] = '1'
        ..['b'] = '2';
      await adapter.clear();
      expect(backend.store, isEmpty);
    });

    test('translates PlatformException on write to SecureStorageException',
        () async {
      backend.failure = PlatformException(code: 'X', message: 'boom');
      await expectLater(
        adapter.writeString('k', 'v'),
        throwsA(
          isA<SecureStorageException>()
              .having((e) => e.message, 'message', contains('write'))
              .having((e) => e.cause, 'cause', isA<PlatformException>()),
        ),
      );
    });

    test('translates PlatformException on read to SecureStorageException',
        () async {
      backend.failure = PlatformException(code: 'X');
      await expectLater(
        adapter.readString('k'),
        throwsA(isA<SecureStorageException>()),
      );
    });

    test('translates PlatformException on delete to SecureStorageException',
        () async {
      backend.failure = PlatformException(code: 'X');
      await expectLater(
        adapter.delete('k'),
        throwsA(isA<SecureStorageException>()),
      );
    });

    test('translates PlatformException on containsKey', () async {
      backend.failure = PlatformException(code: 'X');
      await expectLater(
        adapter.containsKey('k'),
        throwsA(isA<SecureStorageException>()),
      );
    });

    test('translates PlatformException on clear', () async {
      backend.failure = PlatformException(code: 'X');
      await expectLater(
        adapter.clear(),
        throwsA(isA<SecureStorageException>()),
      );
    });
  });
}
