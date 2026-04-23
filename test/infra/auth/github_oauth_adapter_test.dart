import 'package:flutter_test/flutter_test.dart';
import 'package:gitmdscribe/app/controllers/auth_identity_codec.dart';
import 'package:gitmdscribe/domain/entities/auth_session.dart';
import 'package:gitmdscribe/domain/entities/git_identity.dart';
import 'package:gitmdscribe/domain/fakes/fake_secure_storage.dart';
import 'package:gitmdscribe/domain/ports/auth_port.dart';
import 'package:gitmdscribe/domain/ports/secure_storage_port.dart';
import 'package:gitmdscribe/infra/auth/github_oauth_adapter.dart';

/// Scripted in-memory [HttpTransport]. Tests pre-populate [responses] in
/// FIFO order keyed by HTTP verb + URL; the adapter pops the next matching
/// response on each call. All requests are logged to [calls] for
/// interrogation (e.g., slow_down interval bump assertions).
class _FakeHttpTransport implements HttpTransport {
  final List<_Call> calls = [];

  /// Scripted POST responses, consumed in order per URL.
  final Map<String, List<HttpResponse>> postResponses = {};

  /// Scripted GET responses, consumed in order per URL.
  final Map<String, List<HttpResponse>> getResponses = {};

  /// If set, post() throws this error instead of returning a response.
  Object? postThrow;

  @override
  Future<HttpResponse> post(
    String url, {
    Map<String, String> headers = const {},
    Map<String, dynamic> body = const {},
  }) async {
    calls.add(_Call('POST', url, headers, body));
    final t = postThrow;
    if (t != null) throw t;
    final queue = postResponses[url];
    if (queue == null || queue.isEmpty) {
      throw StateError('No scripted POST response for $url');
    }
    return queue.removeAt(0);
  }

  @override
  Future<HttpResponse> get(
    String url, {
    Map<String, String> headers = const {},
  }) async {
    calls.add(_Call('GET', url, headers, const {}));
    final queue = getResponses[url];
    if (queue == null || queue.isEmpty) {
      throw StateError('No scripted GET response for $url');
    }
    return queue.removeAt(0);
  }
}

class _Call {
  _Call(this.verb, this.url, this.headers, this.body);
  final String verb;
  final String url;
  final Map<String, String> headers;
  final Map<String, dynamic> body;
}

class _FakeBrowserLauncher implements BrowserLauncher {
  Uri? opened;
  Object? throwOnOpen;

  @override
  Future<void> openVerificationUri(Uri uri) async {
    opened = uri;
    final t = throwOnOpen;
    if (t != null) throw t;
  }
}

const _deviceCodeUrl = 'https://github.com/login/device/code';
const _tokenUrl = 'https://github.com/login/oauth/access_token';
const _userUrl = 'https://api.github.com/user';

const _identity = GitIdentity(name: 'Ada', email: 'ada@example.com');
const _session = AuthSession(token: 'gho_good', identity: _identity);

Map<String, dynamic> _deviceCodeBody({
  String deviceCode = 'dev_abc',
  String userCode = 'WDJB-MJHT',
  String verificationUri = 'https://github.com/login/device',
  int interval = 5,
  int expiresIn = 900,
}) =>
    {
      'device_code': deviceCode,
      'user_code': userCode,
      'verification_uri': verificationUri,
      'interval': interval,
      'expires_in': expiresIn,
    };

Map<String, dynamic> _userBody({String? name = 'Ada', String? email = 'ada@example.com'}) =>
    {'login': 'ada', 'name': name, 'email': email};

({
  GithubOAuthAdapter adapter,
  _FakeHttpTransport http,
  _FakeBrowserLauncher browser,
  FakeSecureStorage storage,
}) _build() {
  final http = _FakeHttpTransport();
  final browser = _FakeBrowserLauncher();
  final storage = FakeSecureStorage();
  final adapter = GithubOAuthAdapter(
    clientId: 'Iv1.abc',
    http: http,
    browser: browser,
    storage: storage,
  );
  return (adapter: adapter, http: http, browser: browser, storage: storage);
}

DeviceCodeChallenge _challengeWithTinyInterval({
  Duration? expiresIn,
}) =>
    DeviceCodeChallenge(
      deviceCode: 'dev_abc',
      userCode: 'WDJB-MJHT',
      verificationUri: 'https://github.com/login/device',
      pollInterval: const Duration(milliseconds: 1),
      expiresAt: DateTime.now().add(expiresIn ?? const Duration(minutes: 15)),
    );

void main() {
  group('GithubOAuthAdapter.startDeviceFlow', () {
    test('happy path parses challenge fields and opens the browser', () async {
      final env = _build();
      env.http.postResponses[_deviceCodeUrl] = [
        HttpResponse(200, _deviceCodeBody()),
      ];

      final stream = env.adapter.startDeviceFlow();
      final challenge = await stream.first;

      expect(challenge.deviceCode, 'dev_abc');
      expect(challenge.userCode, 'WDJB-MJHT');
      expect(challenge.verificationUri, 'https://github.com/login/device');
      expect(challenge.pollInterval, const Duration(seconds: 5));
      expect(
        challenge.expiresAt.isAfter(DateTime.now()),
        isTrue,
        reason: 'expiresAt should be in the future',
      );

      // Give the fire-and-forget browser call a microtask to run.
      await Future<void>.delayed(Duration.zero);
      expect(env.browser.opened, Uri.parse('https://github.com/login/device'));

      // Verify the request body carried client_id + scope.
      final postCall = env.http.calls.firstWhere((c) => c.verb == 'POST');
      expect(postCall.url, _deviceCodeUrl);
      expect(postCall.body['client_id'], 'Iv1.abc');
      expect(postCall.body['scope'], 'repo');
    });

    test('HTTP 500 throws AuthNetworkFailure', () async {
      final env = _build();
      env.http.postResponses[_deviceCodeUrl] = [
        const HttpResponse(500, {'error': 'server_error'}),
      ];

      final stream = env.adapter.startDeviceFlow();
      await expectLater(stream.first, throwsA(isA<AuthNetworkFailure>()));
    });
  });

  group('GithubOAuthAdapter.pollForToken', () {
    test('authorization_pending twice then access_token persists session',
        () async {
      final env = _build();
      env.http.postResponses[_tokenUrl] = [
        const HttpResponse(200, {'error': 'authorization_pending'}),
        const HttpResponse(200, {'error': 'authorization_pending'}),
        const HttpResponse(200, {
          'access_token': 'gho_good',
          'token_type': 'bearer',
          'scope': 'repo',
        }),
      ];
      env.http.getResponses[_userUrl] = [HttpResponse(200, _userBody())];

      final session = await env.adapter.pollForToken(_challengeWithTinyInterval());

      expect(session.token, 'gho_good');
      expect(session.identity, _identity);

      expect(
        await env.storage.readString(SecureStorageKeys.authToken),
        'gho_good',
      );
      expect(
        await env.storage.readString(SecureStorageKeys.gitIdentity),
        AuthIdentityCodec.encode(_identity),
      );

      // Three token POSTs + one user GET.
      expect(
        env.http.calls.where((c) => c.url == _tokenUrl).length,
        3,
      );
      expect(
        env.http.calls.where((c) => c.url == _userUrl).length,
        1,
      );

      // Token call carried the right grant_type.
      final first = env.http.calls.firstWhere((c) => c.url == _tokenUrl);
      expect(
        first.body['grant_type'],
        'urn:ietf:params:oauth:grant-type:device_code',
      );
      expect(first.body['device_code'], 'dev_abc');
      expect(first.body['client_id'], 'Iv1.abc');
    });

    test('slow_down bumps pollInterval by 5s on the next poll', () async {
      final env = _build();
      // Use a tiny starting interval so the delay is instant in tests; the
      // slow_down bump is still measurable as "+5s beyond the starting value".
      final challenge = DeviceCodeChallenge(
        deviceCode: 'dev_abc',
        userCode: 'WDJB-MJHT',
        verificationUri: 'https://github.com/login/device',
        pollInterval: const Duration(milliseconds: 1),
        expiresAt: DateTime.now().add(const Duration(minutes: 15)),
      );
      env.http.postResponses[_tokenUrl] = [
        const HttpResponse(200, {'error': 'slow_down'}),
        const HttpResponse(200, {
          'access_token': 'gho_good',
          'token_type': 'bearer',
          'scope': 'repo',
        }),
      ];
      env.http.getResponses[_userUrl] = [HttpResponse(200, _userBody())];

      // The adapter has to honour slow_down by adding +5s and then polling.
      // Waiting 5+ seconds in a unit test is unacceptable, so we observe the
      // bumped interval via the adapter's `lastPollInterval` field.
      await env.adapter.pollForToken(challenge);

      expect(
        env.adapter.lastPollInterval,
        const Duration(milliseconds: 1) + const Duration(seconds: 5),
      );
    });

    test('access_denied throws AuthUserDenied', () async {
      final env = _build();
      env.http.postResponses[_tokenUrl] = [
        const HttpResponse(200, {'error': 'access_denied'}),
      ];
      await expectLater(
        env.adapter.pollForToken(_challengeWithTinyInterval()),
        throwsA(isA<AuthUserDenied>()),
      );
    });

    test('expired_token throws AuthDeviceCodeExpired', () async {
      final env = _build();
      env.http.postResponses[_tokenUrl] = [
        const HttpResponse(200, {'error': 'expired_token'}),
      ];
      await expectLater(
        env.adapter.pollForToken(_challengeWithTinyInterval()),
        throwsA(isA<AuthDeviceCodeExpired>()),
      );
    });

    test(
        'local expiry: expiresAt in the past throws AuthDeviceCodeExpired '
        'without any poll HTTP call', () async {
      final env = _build();
      final expired = DeviceCodeChallenge(
        deviceCode: 'dev_abc',
        userCode: 'WDJB-MJHT',
        verificationUri: 'https://github.com/login/device',
        pollInterval: const Duration(milliseconds: 1),
        expiresAt: DateTime.now().subtract(const Duration(seconds: 1)),
      );
      await expectLater(
        env.adapter.pollForToken(expired),
        throwsA(isA<AuthDeviceCodeExpired>()),
      );
      expect(
        env.http.calls.where((c) => c.url == _tokenUrl),
        isEmpty,
        reason: 'Adapter must short-circuit without polling when already expired',
      );
    });
  });

  group('GithubOAuthAdapter.signInWithPat', () {
    test('200 stores token + identity and returns session', () async {
      final env = _build();
      env.http.getResponses[_userUrl] = [HttpResponse(200, _userBody())];

      final session = await env.adapter.signInWithPat('ghp_good');

      expect(session.token, 'ghp_good');
      expect(session.identity, _identity);
      expect(
        await env.storage.readString(SecureStorageKeys.authToken),
        'ghp_good',
      );
      expect(
        await env.storage.readString(SecureStorageKeys.gitIdentity),
        AuthIdentityCodec.encode(_identity),
      );

      // Authorization header was set.
      final getCall = env.http.calls.firstWhere((c) => c.verb == 'GET');
      expect(getCall.headers['Authorization'], 'Bearer ghp_good');
    });

    test('401 throws AuthInvalidToken and leaves storage untouched', () async {
      final env = _build();
      env.http.getResponses[_userUrl] = [
        const HttpResponse(401, {'message': 'Bad credentials'}),
      ];
      await expectLater(
        env.adapter.signInWithPat('ghp_bad'),
        throwsA(isA<AuthInvalidToken>()),
      );
      expect(env.storage.snapshot, isEmpty);
    });

    test('other non-2xx throws AuthNetworkFailure', () async {
      final env = _build();
      env.http.getResponses[_userUrl] = [
        const HttpResponse(500, {'message': 'boom'}),
      ];
      await expectLater(
        env.adapter.signInWithPat('ghp_whatever'),
        throwsA(isA<AuthNetworkFailure>()),
      );
    });
  });

  group('GithubOAuthAdapter.signOut', () {
    test('deletes both authToken and gitIdentity keys', () async {
      final env = _build();
      await env.storage.writeString(SecureStorageKeys.authToken, 'gho_good');
      await env.storage.writeString(
        SecureStorageKeys.gitIdentity,
        AuthIdentityCodec.encode(_identity),
      );

      await env.adapter.signOut();

      expect(env.storage.snapshot, isEmpty);
    });
  });

  group('GithubOAuthAdapter.currentSession', () {
    test('returns null when storage is empty', () async {
      final env = _build();
      expect(await env.adapter.currentSession(), isNull);
    });

    test('returns session when both keys present', () async {
      final env = _build();
      await env.storage.writeString(SecureStorageKeys.authToken, 'gho_good');
      await env.storage.writeString(
        SecureStorageKeys.gitIdentity,
        AuthIdentityCodec.encode(_identity),
      );

      expect(await env.adapter.currentSession(), _session);
    });

    test('returns null when only one key is present', () async {
      final env = _build();
      await env.storage.writeString(SecureStorageKeys.authToken, 'gho_good');
      expect(await env.adapter.currentSession(), isNull);
    });
  });
}
