import '../entities/auth_session.dart';

/// Abstract boundary between the `auth` domain and the outside world
/// (GitHub OAuth, secure storage). The real implementation lives in the
/// infra layer (T6); tests use `FakeAuthPort`.
///
/// See IMPLEMENTATION.md §4.1 and TabletApp-PRD.md §5.10.
abstract class AuthPort {
  /// Starts the OAuth Device Flow. Emits the initial challenge first,
  /// then any updates (e.g. interval increases after `slow_down`).
  Stream<DeviceCodeChallenge> startDeviceFlow();

  /// Polls the token endpoint until success, the flow expires, or the
  /// user denies. Must honour `slow_down` by increasing the polling
  /// interval by 5 s for the rest of the flow.
  Future<AuthSession> pollForToken(DeviceCodeChallenge challenge);

  /// Validates a user-pasted fine-grained PAT by calling `GET /user`.
  /// Returns the resulting session or throws [AuthInvalidToken].
  Future<AuthSession> signInWithPat(String pat);

  /// Clears any persisted session.
  Future<void> signOut();

  /// Returns the current session or `null` if not signed in.
  Future<AuthSession?> currentSession();
}

/// One round of the GitHub Device Flow challenge. Returned by
/// `POST /login/device/code` and consumed by [AuthPort.pollForToken].
class DeviceCodeChallenge {
  const DeviceCodeChallenge({
    required this.deviceCode,
    required this.userCode,
    required this.verificationUri,
    required this.pollInterval,
    required this.expiresAt,
  });

  /// Opaque code exchanged for an access token (never shown to the user).
  final String deviceCode;

  /// Short, human-readable code the user types into the browser
  /// (e.g. `WDJB-MJHT`).
  final String userCode;

  /// URL the user visits to approve the flow.
  final String verificationUri;

  /// Current polling interval. Starts at the value GitHub returned
  /// (typically 5 s) and is bumped by 5 s whenever `slow_down` appears.
  final Duration pollInterval;

  /// Wall-clock expiry of `deviceCode`; after this the user must restart
  /// the flow (GitHub's default is ~15 min).
  final DateTime expiresAt;

  DeviceCodeChallenge copyWith({Duration? pollInterval}) {
    return DeviceCodeChallenge(
      deviceCode: deviceCode,
      userCode: userCode,
      verificationUri: verificationUri,
      pollInterval: pollInterval ?? this.pollInterval,
      expiresAt: expiresAt,
    );
  }
}

/// Sealed root of every error [AuthPort] is allowed to throw. Callers
/// pattern-match on concrete subtypes; we never leak generic `Exception`s.
sealed class AuthError implements Exception {
  const AuthError();
}

/// The PAT or access token was rejected by GitHub (`401`).
class AuthInvalidToken extends AuthError {
  const AuthInvalidToken();
  @override
  String toString() => 'AuthInvalidToken';
}

/// The Device Flow `deviceCode` expired before the user approved.
/// Callers must restart the flow from scratch.
class AuthDeviceCodeExpired extends AuthError {
  const AuthDeviceCodeExpired();
  @override
  String toString() => 'AuthDeviceCodeExpired';
}

/// The user denied the Device Flow request in the browser
/// (`error: access_denied`).
class AuthUserDenied extends AuthError {
  const AuthUserDenied();
  @override
  String toString() => 'AuthUserDenied';
}

/// A transport-level failure (DNS, socket, proxy). The real cause is
/// preserved for logging; the UI should show a generic retry affordance.
class AuthNetworkFailure extends AuthError {
  const AuthNetworkFailure(this.cause);
  final Object cause;
  @override
  String toString() => 'AuthNetworkFailure(cause: $cause)';
}
