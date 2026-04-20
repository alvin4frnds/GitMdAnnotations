import 'package:flutter_test/flutter_test.dart';
import 'package:gitmdannotations_tablet/domain/entities/auth_session.dart';
import 'package:gitmdannotations_tablet/domain/entities/git_identity.dart';
import 'package:gitmdannotations_tablet/domain/fakes/fake_auth_port.dart';
import 'package:gitmdannotations_tablet/domain/ports/auth_port.dart';

void main() {
  const identity = GitIdentity(name: 'Ada', email: 'ada@example.com');
  const session = AuthSession(token: 'gho_good', identity: identity);

  DeviceCodeChallenge challenge({Duration interval = Duration.zero}) {
    return DeviceCodeChallenge(
      deviceCode: 'dev_abc',
      userCode: 'WDJB-MJHT',
      verificationUri: 'https://github.com/login/device',
      pollInterval: interval,
      expiresAt: DateTime.utc(2099, 1, 1),
    );
  }

  group('DeviceCodeChallenge', () {
    test('holds device flow fields', () {
      final c = challenge();
      expect(c.deviceCode, 'dev_abc');
      expect(c.userCode, 'WDJB-MJHT');
      expect(c.verificationUri, 'https://github.com/login/device');
      expect(c.pollInterval, Duration.zero);
      expect(c.expiresAt, DateTime.utc(2099, 1, 1));
    });
  });

  group('FakeAuthPort — startDeviceFlow', () {
    test('emits the configured challenge as the first event', () async {
      final fake = FakeAuthPort()..nextChallenge = challenge();
      final events = await fake.startDeviceFlow().take(1).toList();
      expect(events, hasLength(1));
      expect(events.first.userCode, 'WDJB-MJHT');
    });

    test('throws StateError if nextChallenge is null', () {
      final fake = FakeAuthPort();
      expect(fake.startDeviceFlow, throwsStateError);
    });
  });

  group('FakeAuthPort — pollForToken', () {
    test('fresh install Device Flow returns and persists session', () async {
      final fake = FakeAuthPort()
        ..nextChallenge = challenge()
        ..pollScript.add(PollSuccess(session));

      final got = await fake.pollForToken(fake.nextChallenge!);

      expect(got, session);
      expect(await fake.currentSession(), session);
    });

    test('slow_down bumps poll interval by 5s for the remainder of flow',
        () async {
      final fake = FakeAuthPort()
        ..nextChallenge = challenge()
        ..pollScript.addAll([
          const PollSlowDown(),
          PollSuccess(session),
        ]);

      final stream = fake.startDeviceFlow();
      final collected = <DeviceCodeChallenge>[];
      final sub = stream.listen(collected.add);

      await fake.pollForToken(fake.nextChallenge!);
      await sub.cancel();

      expect(fake.lastIntervalUsed, const Duration(seconds: 5));
      expect(collected, hasLength(2));
      expect(collected.first.pollInterval, Duration.zero);
      expect(collected.last.pollInterval, const Duration(seconds: 5));
    });

    test('authorization_pending keeps polling and succeeds', () async {
      final fake = FakeAuthPort()
        ..nextChallenge = challenge()
        ..pollScript.addAll([
          const PollAuthorizationPending(),
          const PollAuthorizationPending(),
          PollSuccess(session),
        ]);

      final got = await fake.pollForToken(fake.nextChallenge!);
      expect(got, session);
      expect(fake.lastIntervalUsed, Duration.zero);
    });

    test('access_denied throws AuthUserDenied and does not persist', () async {
      final fake = FakeAuthPort()
        ..nextChallenge = challenge()
        ..pollScript.add(const PollAccessDenied());

      await expectLater(
        fake.pollForToken(fake.nextChallenge!),
        throwsA(isA<AuthUserDenied>()),
      );
      expect(await fake.currentSession(), isNull);
    });

    test('expired_token throws AuthDeviceCodeExpired and does not persist',
        () async {
      final fake = FakeAuthPort()
        ..nextChallenge = challenge()
        ..pollScript.add(const PollExpiredToken());

      await expectLater(
        fake.pollForToken(fake.nextChallenge!),
        throwsA(isA<AuthDeviceCodeExpired>()),
      );
      expect(await fake.currentSession(), isNull);
    });

    test('empty poll script throws StateError', () async {
      final fake = FakeAuthPort()..nextChallenge = challenge();
      await expectLater(
        fake.pollForToken(fake.nextChallenge!),
        throwsStateError,
      );
    });
  });

  group('FakeAuthPort — signInWithPat', () {
    test('valid scripted PAT returns session and persists it', () async {
      final fake = FakeAuthPort()
        ..patScript['good_pat'] = PatResponse.success(session);

      final got = await fake.signInWithPat('good_pat');

      expect(got, session);
      expect(await fake.currentSession(), session);
    });

    test('unlisted PAT throws AuthInvalidToken', () async {
      final fake = FakeAuthPort();
      await expectLater(
        fake.signInWithPat('never_heard_of_it'),
        throwsA(isA<AuthInvalidToken>()),
      );
      expect(await fake.currentSession(), isNull);
    });

    test('PatResponse.error throws the configured error', () async {
      final fake = FakeAuthPort()
        ..patScript['revoked'] = PatResponse.error(const AuthInvalidToken());
      await expectLater(
        fake.signInWithPat('revoked'),
        throwsA(isA<AuthInvalidToken>()),
      );
    });

    test('revoked-token recovery: stored session + invalid new PAT', () async {
      final fake = FakeAuthPort()..storedSession = session;
      await expectLater(
        fake.signInWithPat('revoked_pat'),
        throwsA(isA<AuthInvalidToken>()),
      );
    });
  });

  group('FakeAuthPort — signOut & currentSession', () {
    test('signOut clears storedSession', () async {
      final fake = FakeAuthPort()..storedSession = session;
      expect(await fake.currentSession(), session);
      await fake.signOut();
      expect(await fake.currentSession(), isNull);
    });

    test('currentSession returns null when nothing is stored', () async {
      final fake = FakeAuthPort();
      expect(await fake.currentSession(), isNull);
    });
  });

  group('AuthError hierarchy', () {
    test('all auth errors are AuthError subtypes', () {
      expect(const AuthInvalidToken(), isA<AuthError>());
      expect(const AuthDeviceCodeExpired(), isA<AuthError>());
      expect(const AuthUserDenied(), isA<AuthError>());
      expect(AuthNetworkFailure(Exception('boom')), isA<AuthError>());
    });

    test('AuthNetworkFailure preserves the wrapped cause', () {
      final cause = Exception('socket down');
      final err = AuthNetworkFailure(cause);
      expect(err.cause, cause);
    });
  });
}
