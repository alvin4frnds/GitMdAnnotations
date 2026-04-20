import 'dart:async';

import '../entities/auth_session.dart';
import '../ports/auth_port.dart';

/// In-memory, scripted implementation of [AuthPort] for domain tests.
/// Tests populate [pollScript], [patScript], [nextChallenge], and
/// [storedSession], then drive the port exactly like production code.
class FakeAuthPort implements AuthPort {
  /// Scripted responses consumed in order by [pollForToken].
  final List<PollResponse> pollScript = [];

  /// Map of PAT -> outcome. Unknown PATs throw [AuthInvalidToken].
  final Map<String, PatResponse> patScript = {};

  /// The challenge [startDeviceFlow] emits as its first event. Must be
  /// set before calling [startDeviceFlow] or [pollForToken].
  DeviceCodeChallenge? nextChallenge;

  /// The currently-persisted session (what [currentSession] returns).
  AuthSession? storedSession;

  /// Last interval actually slept on during a [pollForToken] run.
  /// Lets tests assert the slow_down bump without waiting.
  Duration? lastIntervalUsed;

  final StreamController<DeviceCodeChallenge> _challenges =
      StreamController<DeviceCodeChallenge>.broadcast();

  @override
  Stream<DeviceCodeChallenge> startDeviceFlow() {
    final initial = nextChallenge;
    if (initial == null) {
      throw StateError('FakeAuthPort.nextChallenge must be set before '
          'calling startDeviceFlow()');
    }
    // Emit the initial challenge asynchronously so listeners that subscribe
    // synchronously after this call still receive it.
    scheduleMicrotask(() => _challenges.add(initial));
    return _challenges.stream;
  }

  @override
  Future<AuthSession> pollForToken(DeviceCodeChallenge challenge) async {
    var current = challenge;
    for (var i = 0; i < pollScript.length; i++) {
      await Future<void>.delayed(current.pollInterval);
      lastIntervalUsed = current.pollInterval;
      final response = pollScript[i];
      switch (response) {
        case PollAuthorizationPending():
          continue;
        case PollSlowDown():
          current = current.copyWith(
            pollInterval: current.pollInterval + const Duration(seconds: 5),
          );
          nextChallenge = current;
          _challenges.add(current);
          continue;
        case PollSuccess(:final session):
          storedSession = session;
          return session;
        case PollAccessDenied():
          throw const AuthUserDenied();
        case PollExpiredToken():
          throw const AuthDeviceCodeExpired();
      }
    }
    throw StateError('unexpected poll: FakeAuthPort.pollScript was exhausted');
  }

  @override
  Future<AuthSession> signInWithPat(String pat) async {
    final scripted = patScript[pat];
    if (scripted == null) {
      throw const AuthInvalidToken();
    }
    return switch (scripted) {
      PatSuccess(:final session) => _persist(session),
      PatError(:final error) => throw error,
    };
  }

  AuthSession _persist(AuthSession s) {
    storedSession = s;
    return s;
  }

  @override
  Future<void> signOut() async {
    storedSession = null;
  }

  @override
  Future<AuthSession?> currentSession() async => storedSession;

  /// Release the internal broadcast controller. Tests that call
  /// [startDeviceFlow] should invoke this in tearDown if they care about
  /// pending subscriptions; single-shot tests can ignore it.
  Future<void> dispose() => _challenges.close();
}

/// One scripted response for [FakeAuthPort.pollForToken].
sealed class PollResponse {
  const PollResponse();
}

class PollAuthorizationPending extends PollResponse {
  const PollAuthorizationPending();
}

class PollSlowDown extends PollResponse {
  const PollSlowDown();
}

class PollSuccess extends PollResponse {
  const PollSuccess(this.session);
  final AuthSession session;
}

class PollAccessDenied extends PollResponse {
  const PollAccessDenied();
}

class PollExpiredToken extends PollResponse {
  const PollExpiredToken();
}

/// One scripted outcome for [FakeAuthPort.signInWithPat].
sealed class PatResponse {
  const PatResponse();
  const factory PatResponse.success(AuthSession session) = PatSuccess;
  const factory PatResponse.error(AuthError error) = PatError;
}

class PatSuccess extends PatResponse {
  const PatSuccess(this.session);
  final AuthSession session;
}

class PatError extends PatResponse {
  const PatError(this.error);
  final AuthError error;
}
