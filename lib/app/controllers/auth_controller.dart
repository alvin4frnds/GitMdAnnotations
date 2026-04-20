import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/auth_session.dart';
import '../../domain/ports/auth_port.dart';
import '../../domain/ports/secure_storage_port.dart';
import '../providers/auth_providers.dart';
import 'auth_identity_codec.dart';

/// Top-level auth state. Sealed so UI `switch`es are exhaustive.
sealed class AuthState {
  const AuthState();
}

class AuthSignedOut extends AuthState {
  const AuthSignedOut();
}

class AuthDeviceFlowAwaitingUser extends AuthState {
  const AuthDeviceFlowAwaitingUser(this.challenge);
  final DeviceCodeChallenge challenge;
}

class AuthSignedIn extends AuthState {
  const AuthSignedIn(this.session);
  final AuthSession session;
}

/// Wires [AuthPort] + [SecureStoragePort] into a Riverpod `AsyncNotifier`.
/// Transitions are driven by explicit intents (`startDeviceFlow`, `signIn…`,
/// `signOut`, `handleTokenRevoked`) and by the restored state in [build].
class AuthController extends AsyncNotifier<AuthState> {
  AuthPort get _auth => ref.read(authPortProvider);
  SecureStoragePort get _storage => ref.read(secureStorageProvider);

  @override
  Future<AuthState> build() async {
    final token = await _storage.readString(SecureStorageKeys.authToken);
    final identityBlob =
        await _storage.readString(SecureStorageKeys.gitIdentity);
    if (token == null || identityBlob == null) return const AuthSignedOut();
    final identity = AuthIdentityCodec.decode(identityBlob);
    if (identity == null) return const AuthSignedOut();
    return AuthSignedIn(AuthSession(token: token, identity: identity));
  }

  Future<void> startDeviceFlow() async {
    if (state.isLoading) return;
    state = const AsyncValue.loading();
    try {
      final session = await _runDeviceFlow();
      await _persist(session);
      state = AsyncValue.data(AuthSignedIn(session));
    } on AuthError catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<AuthSession> _runDeviceFlow() async {
    var current = Completer<DeviceCodeChallenge>();
    late StreamSubscription<DeviceCodeChallenge> sub;
    DeviceCodeChallenge? latest;
    sub = _auth.startDeviceFlow().listen((c) {
      latest = c;
      if (!current.isCompleted) current.complete(c);
    });
    try {
      final first = await current.future;
      state = AsyncValue.data(AuthDeviceFlowAwaitingUser(first));
      final session = await _auth.pollForToken(latest ?? first);
      return session;
    } finally {
      await sub.cancel();
    }
  }

  Future<void> signInWithPat(String pat) async {
    if (state.isLoading) return;
    state = const AsyncValue.loading();
    try {
      final session = await _auth.signInWithPat(pat);
      await _persist(session);
      state = AsyncValue.data(AuthSignedIn(session));
    } on AuthError catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> signOut() async {
    await _auth.signOut();
    await _clearStorage();
    state = const AsyncValue.data(AuthSignedOut());
  }

  /// Called by adapters when a 401 indicates the token has been revoked at
  /// github.com. Same outcome as [signOut] for MVP.
  Future<void> handleTokenRevoked() async {
    await _auth.signOut();
    await _clearStorage();
    state = const AsyncValue.data(AuthSignedOut());
  }

  Future<void> _persist(AuthSession session) async {
    await _storage.writeString(SecureStorageKeys.authToken, session.token);
    await _storage.writeString(
      SecureStorageKeys.gitIdentity,
      AuthIdentityCodec.encode(session.identity),
    );
  }

  Future<void> _clearStorage() async {
    await _storage.delete(SecureStorageKeys.authToken);
    await _storage.delete(SecureStorageKeys.gitIdentity);
  }
}
