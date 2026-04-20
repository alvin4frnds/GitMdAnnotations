import '../ports/secure_storage_port.dart';

/// In-memory [SecureStoragePort] implementation for domain tests. Pure
/// Dart; no Flutter, no secure-storage package. Semantics mirror the
/// production Keystore adapter closely enough that the same tests can run
/// against either.
class FakeSecureStorage implements SecureStoragePort {
  final Map<String, String> _store = <String, String>{};

  /// Read-only view of the backing map, useful for assertions.
  Map<String, String> get snapshot => Map.unmodifiable(_store);

  @override
  Future<void> writeString(String key, String value) async {
    _store[key] = value;
  }

  @override
  Future<String?> readString(String key) async => _store[key];

  @override
  Future<void> delete(String key) async {
    _store.remove(key);
  }

  @override
  Future<bool> containsKey(String key) async => _store.containsKey(key);

  @override
  Future<void> clear() async {
    _store.clear();
  }
}
