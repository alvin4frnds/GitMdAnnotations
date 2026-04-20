import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitmdannotations_tablet/app/controllers/auth_controller.dart';
import 'package:gitmdannotations_tablet/app/controllers/auth_identity_codec.dart';
import 'package:gitmdannotations_tablet/app/providers/auth_providers.dart';
import 'package:gitmdannotations_tablet/domain/entities/auth_session.dart';
import 'package:gitmdannotations_tablet/domain/entities/git_identity.dart';
import 'package:gitmdannotations_tablet/domain/fakes/fake_auth_port.dart';
import 'package:gitmdannotations_tablet/domain/fakes/fake_secure_storage.dart';
import 'package:gitmdannotations_tablet/domain/ports/auth_port.dart';
import 'package:gitmdannotations_tablet/domain/ports/secure_storage_port.dart';

/// Smallest DeviceCodeChallenge with zero-interval polling so the fake
/// doesn't add real latency.
DeviceCodeChallenge _challenge() => DeviceCodeChallenge(
      deviceCode: 'dev_abc',
      userCode: 'WDJB-MJHT',
      verificationUri: 'https://github.com/login/device',
      pollInterval: Duration.zero,
      expiresAt: DateTime.utc(2099, 1, 1),
    );

const _identity = GitIdentity(name: 'Ada', email: 'ada@example.com');
const _session = AuthSession(token: 'gho_good', identity: _identity);

({ProviderContainer container, FakeAuthPort auth, FakeSecureStorage storage})
    _buildContainer({
  FakeAuthPort? auth,
  FakeSecureStorage? storage,
}) {
  final a = auth ?? FakeAuthPort();
  final s = storage ?? FakeSecureStorage();
  final container = ProviderContainer(overrides: [
    authPortProvider.overrideWithValue(a),
    secureStorageProvider.overrideWithValue(s),
  ]);
  addTearDown(container.dispose);
  return (container: container, auth: a, storage: s);
}

void main() {
  group('AuthController.build()', () {
    test('no stored session → AuthSignedOut', () async {
      final env = _buildContainer();
      final state = await env.container.read(authControllerProvider.future);
      expect(state, isA<AuthSignedOut>());
    });

    test('stored token + identity → AuthSignedIn', () async {
      final storage = FakeSecureStorage();
      await storage.writeString(SecureStorageKeys.authToken, 'gho_good');
      await storage.writeString(
        SecureStorageKeys.gitIdentity,
        AuthIdentityCodec.encode(_identity),
      );

      final env = _buildContainer(storage: storage);
      final state = await env.container.read(authControllerProvider.future);
      expect(state, isA<AuthSignedIn>());
      expect((state as AuthSignedIn).session, _session);
    });

    test('orphaned token only (missing identity) → AuthSignedOut', () async {
      final storage = FakeSecureStorage();
      await storage.writeString(SecureStorageKeys.authToken, 'gho_good');
      final env = _buildContainer(storage: storage);
      final state = await env.container.read(authControllerProvider.future);
      expect(state, isA<AuthSignedOut>());
    });
  });

  group('AuthController.startDeviceFlow()', () {
    test('happy path: loading → awaitingUser → signedIn + persists', () async {
      final auth = FakeAuthPort()
        ..nextChallenge = _challenge()
        ..pollScript.add(PollSuccess(_session));
      final env = _buildContainer(auth: auth);

      // Wait for initial build.
      await env.container.read(authControllerProvider.future);

      final states = <AuthState>[];
      final errors = <Object>[];
      final sub = env.container.listen<AsyncValue<AuthState>>(
        authControllerProvider,
        (prev, next) {
          next.when(
            data: states.add,
            error: (e, _) => errors.add(e),
            loading: () {},
          );
        },
      );

      await env.container
          .read(authControllerProvider.notifier)
          .startDeviceFlow();

      sub.close();

      // We should have seen an AwaitingUser state followed by SignedIn.
      expect(states.whereType<AuthDeviceFlowAwaitingUser>(), isNotEmpty);
      expect(states.last, isA<AuthSignedIn>());
      expect((states.last as AuthSignedIn).session, _session);

      expect(
        await env.storage.readString(SecureStorageKeys.authToken),
        'gho_good',
      );
      expect(
        await env.storage.readString(SecureStorageKeys.gitIdentity),
        AuthIdentityCodec.encode(_identity),
      );
      expect(errors, isEmpty);
    });

    test('slow_down then success still persists the session', () async {
      final auth = FakeAuthPort()
        ..nextChallenge = _challenge()
        ..pollScript.addAll([
          const PollSlowDown(),
          PollSuccess(_session),
        ]);
      final env = _buildContainer(auth: auth);
      await env.container.read(authControllerProvider.future);

      await env.container
          .read(authControllerProvider.notifier)
          .startDeviceFlow();

      final state = env.container.read(authControllerProvider).value;
      expect(state, isA<AuthSignedIn>());
      expect(
        await env.storage.readString(SecureStorageKeys.authToken),
        'gho_good',
      );
    });

    test('user denied → AsyncValue.error(AuthUserDenied), storage clean',
        () async {
      final auth = FakeAuthPort()
        ..nextChallenge = _challenge()
        ..pollScript.add(const PollAccessDenied());
      final env = _buildContainer(auth: auth);
      await env.container.read(authControllerProvider.future);

      await env.container
          .read(authControllerProvider.notifier)
          .startDeviceFlow();

      final async = env.container.read(authControllerProvider);
      expect(async.hasError, isTrue);
      expect(async.error, isA<AuthUserDenied>());
      expect(env.storage.snapshot, isEmpty);
    });

    test('expired code → AsyncValue.error(AuthDeviceCodeExpired)', () async {
      final auth = FakeAuthPort()
        ..nextChallenge = _challenge()
        ..pollScript.add(const PollExpiredToken());
      final env = _buildContainer(auth: auth);
      await env.container.read(authControllerProvider.future);

      await env.container
          .read(authControllerProvider.notifier)
          .startDeviceFlow();

      final async = env.container.read(authControllerProvider);
      expect(async.hasError, isTrue);
      expect(async.error, isA<AuthDeviceCodeExpired>());
      expect(env.storage.snapshot, isEmpty);
    });

    test('re-entrant startDeviceFlow is guarded while loading', () async {
      final auth = FakeAuthPort()
        ..nextChallenge = _challenge()
        ..pollScript.add(PollSuccess(_session));
      final env = _buildContainer(auth: auth);
      await env.container.read(authControllerProvider.future);

      final notifier = env.container.read(authControllerProvider.notifier);

      // Fire both calls; only the first should have driven the flow.
      final first = notifier.startDeviceFlow();
      final second = notifier.startDeviceFlow();
      await Future.wait<void>([first, second]);

      // Fake's pollScript would have thrown StateError if a second
      // run consumed another response. Storage holds the single session.
      expect(
        await env.storage.readString(SecureStorageKeys.authToken),
        'gho_good',
      );
    });
  });

  group('AuthController.signInWithPat()', () {
    test('valid PAT persists session and transitions to AuthSignedIn',
        () async {
      final auth = FakeAuthPort()
        ..patScript['good_pat'] = PatResponse.success(_session);
      final env = _buildContainer(auth: auth);
      await env.container.read(authControllerProvider.future);

      await env.container
          .read(authControllerProvider.notifier)
          .signInWithPat('good_pat');

      final state = env.container.read(authControllerProvider).value;
      expect(state, isA<AuthSignedIn>());
      expect(
        await env.storage.readString(SecureStorageKeys.authToken),
        'gho_good',
      );
    });

    test('invalid PAT errors then later valid PAT recovers', () async {
      final auth = FakeAuthPort()
        ..patScript['good_pat'] = PatResponse.success(_session);
      final env = _buildContainer(auth: auth);
      await env.container.read(authControllerProvider.future);

      await env.container
          .read(authControllerProvider.notifier)
          .signInWithPat('nope');

      var async = env.container.read(authControllerProvider);
      expect(async.hasError, isTrue);
      expect(async.error, isA<AuthInvalidToken>());
      expect(env.storage.snapshot, isEmpty);

      await env.container
          .read(authControllerProvider.notifier)
          .signInWithPat('good_pat');

      async = env.container.read(authControllerProvider);
      expect(async.value, isA<AuthSignedIn>());
    });
  });

  group('AuthController.signOut()', () {
    test('clears both storage keys and returns to AuthSignedOut', () async {
      final storage = FakeSecureStorage();
      await storage.writeString(SecureStorageKeys.authToken, 'gho_good');
      await storage.writeString(
        SecureStorageKeys.gitIdentity,
        AuthIdentityCodec.encode(_identity),
      );
      final env = _buildContainer(storage: storage);
      await env.container.read(authControllerProvider.future);

      await env.container.read(authControllerProvider.notifier).signOut();

      final state = env.container.read(authControllerProvider).value;
      expect(state, isA<AuthSignedOut>());
      expect(env.storage.snapshot, isEmpty);
    });
  });

  group('AuthController.handleTokenRevoked()', () {
    test('clears storage and returns to AuthSignedOut', () async {
      final storage = FakeSecureStorage();
      await storage.writeString(SecureStorageKeys.authToken, 'gho_good');
      await storage.writeString(
        SecureStorageKeys.gitIdentity,
        AuthIdentityCodec.encode(_identity),
      );
      final env = _buildContainer(storage: storage);
      await env.container.read(authControllerProvider.future);

      await env.container
          .read(authControllerProvider.notifier)
          .handleTokenRevoked();

      final state = env.container.read(authControllerProvider).value;
      expect(state, isA<AuthSignedOut>());
      expect(env.storage.snapshot, isEmpty);
    });
  });

  group('AuthIdentityCodec', () {
    test('round-trips a plain identity', () {
      const id = GitIdentity(name: 'Ada Lovelace', email: 'ada@example.com');
      final encoded = AuthIdentityCodec.encode(id);
      expect(AuthIdentityCodec.decode(encoded), id);
    });

    test('round-trips an identity whose email contains a literal pipe', () {
      const id = GitIdentity(name: 'Pipe|Name', email: 'wei|rd@example.com');
      final encoded = AuthIdentityCodec.encode(id);
      // The pipe separator must be unambiguous — there should be exactly
      // one un-escaped pipe in the encoded form.
      final unescaped = encoded.replaceAll('%7C', '');
      expect('|'.allMatches(unescaped), hasLength(1));
      expect(AuthIdentityCodec.decode(encoded), id);
    });

    test('decode of malformed blob returns null', () {
      expect(AuthIdentityCodec.decode('no-separator'), isNull);
    });
  });
}
