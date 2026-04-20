import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../domain/ports/secure_storage_port.dart';

/// Narrow surface the [KeystoreAdapter] calls on `flutter_secure_storage`.
/// Exists solely so the adapter is unit-testable without a Flutter platform
/// channel (see `test/infra/storage/keystore_adapter_test.dart`).
abstract class SecureBackend {
  Future<void> write({required String key, required String value});
  Future<String?> read({required String key});
  Future<void> delete({required String key});
  Future<bool> containsKey({required String key});
  Future<void> deleteAll();
}

/// Production [SecureStoragePort] backed by Android Keystore via
/// `flutter_secure_storage`. Translates `PlatformException` into the
/// domain-typed [SecureStorageException] so `lib/domain/**` stays Flutter-
/// free. See IMPLEMENTATION.md §4.1 FR-3–5, TabletApp-PRD.md §5.10.3.
class KeystoreAdapter implements SecureStoragePort {
  KeystoreAdapter({SecureBackend? backend})
      : _backend = backend ?? _DefaultSecureBackend();

  final SecureBackend _backend;

  @override
  Future<void> writeString(String key, String value) =>
      _wrap('write', () => _backend.write(key: key, value: value));

  @override
  Future<String?> readString(String key) =>
      _wrap('read', () => _backend.read(key: key));

  @override
  Future<void> delete(String key) =>
      _wrap('delete', () => _backend.delete(key: key));

  @override
  Future<bool> containsKey(String key) =>
      _wrap('containsKey', () => _backend.containsKey(key: key));

  @override
  Future<void> clear() => _wrap('clear', _backend.deleteAll);

  Future<T> _wrap<T>(String op, Future<T> Function() body) async {
    try {
      return await body();
    } on PlatformException catch (e) {
      throw SecureStorageException('secure storage $op failed', cause: e);
    }
  }
}

class _DefaultSecureBackend implements SecureBackend {
  _DefaultSecureBackend()
      : _storage = const FlutterSecureStorage(
          aOptions: AndroidOptions(encryptedSharedPreferences: true),
        );

  final FlutterSecureStorage _storage;

  @override
  Future<void> write({required String key, required String value}) =>
      _storage.write(key: key, value: value);

  @override
  Future<String?> read({required String key}) => _storage.read(key: key);

  @override
  Future<void> delete({required String key}) => _storage.delete(key: key);

  @override
  Future<bool> containsKey({required String key}) =>
      _storage.containsKey(key: key);

  @override
  Future<void> deleteAll() => _storage.deleteAll();
}
