import 'dart:async';

import '../../app/controllers/auth_identity_codec.dart';
import '../../domain/entities/auth_session.dart';
import '../../domain/entities/git_identity.dart';
import '../../domain/ports/auth_port.dart';
import '../../domain/ports/secure_storage_port.dart';
import '_default_browser_launcher.dart';
import '_default_http_transport.dart';

/// Thin transport seam used by [GithubOAuthAdapter] so unit tests can avoid
/// real network I/O. The production ctor constructs the default
/// implementation backed by `dio`.
abstract class HttpTransport {
  Future<HttpResponse> post(
    String url, {
    Map<String, String> headers,
    Map<String, dynamic> body,
  });

  Future<HttpResponse> get(
    String url, {
    Map<String, String> headers,
  });
}

/// Parsed HTTP response used by [HttpTransport]. Only the status code and
/// JSON-decoded body are exposed — header/cookie handling is out of scope
/// for the auth flow.
class HttpResponse {
  const HttpResponse(this.statusCode, this.body);
  final int statusCode;
  final Map<String, dynamic> body;
}

/// Launches the verification URL in a Chrome Custom Tab. Test seam so unit
/// tests can assert that the adapter hands the URI to the browser without
/// requiring a real `url_launcher` platform channel.
abstract class BrowserLauncher {
  Future<void> openVerificationUri(Uri uri);
}

/// Production [AuthPort] backed by the GitHub Device Flow (§5.10 of the
/// PRD / §4.1 of IMPLEMENTATION.md). The transport and browser launcher
/// are injected so the adapter is unit-testable; real infrastructure is
/// constructed by default.
class GithubOAuthAdapter implements AuthPort {
  GithubOAuthAdapter({
    required this.clientId,
    required this.storage,
    HttpTransport? http,
    BrowserLauncher? browser,
  })  : http = http ?? DefaultHttpTransport(),
        browser = browser ?? DefaultBrowserLauncher();

  final String clientId;
  final HttpTransport http;
  final BrowserLauncher browser;
  final SecureStoragePort storage;

  /// Last interval actually slept on during [pollForToken]. Exposed as a
  /// test seam so poll-timing assertions (e.g. the slow_down bump) don't
  /// require real multi-second delays.
  Duration? lastPollInterval;

  static const _deviceCodeUrl = 'https://github.com/login/device/code';
  static const _tokenUrl = 'https://github.com/login/oauth/access_token';
  static const _userUrl = 'https://api.github.com/user';
  static const _grantType = 'urn:ietf:params:oauth:grant-type:device_code';

  @override
  Stream<DeviceCodeChallenge> startDeviceFlow() async* {
    final HttpResponse res;
    try {
      res = await http.post(
        _deviceCodeUrl,
        headers: const {'Accept': 'application/json'},
        body: {'client_id': clientId, 'scope': 'repo'},
      );
    } catch (e) {
      throw AuthNetworkFailure(e);
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw AuthNetworkFailure('device/code HTTP ${res.statusCode}');
    }
    final body = res.body;
    final interval = (body['interval'] as num?)?.toInt() ?? 5;
    final expiresIn = (body['expires_in'] as num?)?.toInt() ?? 900;
    final challenge = DeviceCodeChallenge(
      deviceCode: body['device_code'] as String,
      userCode: body['user_code'] as String,
      verificationUri: body['verification_uri'] as String,
      pollInterval: Duration(seconds: interval),
      expiresAt: DateTime.now().add(Duration(seconds: expiresIn)),
    );
    // Fire-and-forget browser launch; swallow any failure so the poller
    // still has a chance to succeed if the user opened the URL manually.
    // Kicked off *before* yielding so subscribers that only consume the
    // first event still trigger the launch.
    unawaited(_launchBrowserQuietly(Uri.parse(challenge.verificationUri)));
    yield challenge;
  }

  Future<void> _launchBrowserQuietly(Uri uri) async {
    try {
      await browser.openVerificationUri(uri);
    } catch (_) {
      // TODO: logger — log at WARNING, no PII beyond the verification URL.
    }
  }

  @override
  Future<AuthSession> pollForToken(DeviceCodeChallenge challenge) async {
    var current = challenge;
    while (true) {
      if (DateTime.now().isAfter(current.expiresAt)) {
        throw const AuthDeviceCodeExpired();
      }
      await Future<void>.delayed(current.pollInterval);
      lastPollInterval = current.pollInterval;

      final HttpResponse res;
      try {
        res = await http.post(
          _tokenUrl,
          headers: const {'Accept': 'application/json'},
          body: {
            'client_id': clientId,
            'device_code': current.deviceCode,
            'grant_type': _grantType,
          },
        );
      } catch (e) {
        throw AuthNetworkFailure(e);
      }

      final body = res.body;
      if (body['access_token'] is String) {
        final token = body['access_token'] as String;
        return _finaliseSession(token);
      }
      current = _handlePollError(body, current);
    }
  }

  DeviceCodeChallenge _handlePollError(
    Map<String, dynamic> body,
    DeviceCodeChallenge current,
  ) {
    final error = body['error'];
    switch (error) {
      case 'authorization_pending':
        return current;
      case 'slow_down':
        return current.copyWith(
          pollInterval: current.pollInterval + const Duration(seconds: 5),
        );
      case 'access_denied':
        throw const AuthUserDenied();
      case 'expired_token':
        throw const AuthDeviceCodeExpired();
      default:
        throw AuthNetworkFailure(error ?? 'unknown poll error');
    }
  }

  @override
  Future<AuthSession> signInWithPat(String pat) async {
    final HttpResponse res;
    try {
      res = await http.get(
        _userUrl,
        headers: _authHeaders(pat),
      );
    } catch (e) {
      throw AuthNetworkFailure(e);
    }
    if (res.statusCode == 401) throw const AuthInvalidToken();
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw AuthNetworkFailure('/user HTTP ${res.statusCode}');
    }
    final identity = _identityFromUserBody(res.body);
    await _persist(pat, identity);
    return AuthSession(token: pat, identity: identity);
  }

  @override
  Future<void> signOut() async {
    await storage.delete(SecureStorageKeys.authToken);
    await storage.delete(SecureStorageKeys.gitIdentity);
  }

  @override
  Future<AuthSession?> currentSession() async {
    final token = await storage.readString(SecureStorageKeys.authToken);
    final blob = await storage.readString(SecureStorageKeys.gitIdentity);
    if (token == null || blob == null) return null;
    final identity = AuthIdentityCodec.decode(blob);
    if (identity == null) return null;
    return AuthSession(token: token, identity: identity);
  }

  Future<AuthSession> _finaliseSession(String token) async {
    final HttpResponse userRes;
    try {
      userRes = await http.get(_userUrl, headers: _authHeaders(token));
    } catch (e) {
      throw AuthNetworkFailure(e);
    }
    if (userRes.statusCode == 401) throw const AuthInvalidToken();
    if (userRes.statusCode < 200 || userRes.statusCode >= 300) {
      throw AuthNetworkFailure('/user HTTP ${userRes.statusCode}');
    }
    final identity = _identityFromUserBody(userRes.body);
    await _persist(token, identity);
    return AuthSession(token: token, identity: identity);
  }

  Map<String, String> _authHeaders(String token) => {
        'Authorization': 'Bearer $token',
        'Accept': 'application/vnd.github+json',
      };

  /// Resolve the commit identity from `GET /user`. `body['email']` is
  /// frequently null for users with private email addresses; for MVP we
  /// accept an empty string. Post-MVP follow-up: resolve the primary email
  /// via `GET /user/emails` when the primary is not exposed on `/user`.
  GitIdentity _identityFromUserBody(Map<String, dynamic> body) {
    final name = (body['name'] as String?) ?? (body['login'] as String? ?? '');
    final email = (body['email'] as String?) ?? '';
    return GitIdentity(name: name, email: email);
  }

  Future<void> _persist(String token, GitIdentity identity) async {
    await storage.writeString(SecureStorageKeys.authToken, token);
    await storage.writeString(
      SecureStorageKeys.gitIdentity,
      AuthIdentityCodec.encode(identity),
    );
  }
}
