import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/providers/annotation_providers.dart';
import 'app/providers/auth_providers.dart';
import 'app/providers/spec_providers.dart';
import 'app/providers/sync_providers.dart';
import 'domain/entities/auth_session.dart';
import 'domain/entities/git_identity.dart';
import 'domain/entities/repo_ref.dart';
import 'domain/fakes/fake_auth_port.dart';
import 'domain/fakes/fake_file_system.dart';
import 'domain/fakes/fake_git_port.dart';
import 'domain/fakes/fake_secure_storage.dart';
import 'domain/ports/auth_port.dart';
import 'domain/ports/secure_storage_port.dart';
import 'infra/auth/github_oauth_adapter.dart';
import 'infra/clock/system_clock.dart';
import 'infra/fs/fs_adapter.dart';
import 'infra/git/git_adapter.dart';
import 'infra/id/system_id_generator.dart';
import 'infra/storage/keystore_adapter.dart';

/// Composition-root mode flag. `real` binds production adapters (OAuth,
/// libgit2dart, Keystore, on-disk filesystem); `mockup` binds the
/// in-memory fakes so the mockup browser can flip through all 12 screens
/// without touching a keychain or the network.
enum AppMode { real, mockup }

/// BLOCKER: real OAuth client id is still `OVERRIDE_ME`. The real GitHub
/// OAuth App isn't registered yet; this const lives here as a single
/// anchor so the follow-up patch is a one-line change. Do NOT try to sign
/// in with `--dart-define=APP_MODE=real` until this is replaced.
const String _prodClientId = 'OVERRIDE_ME';

/// The demo repo mockup mode renders under. Matches the literal
/// `payments-api` string baked into `JobListScreen`'s old stub chrome so
/// that flipping through the mockup browser still shows the same header.
const RepoRef _mockupRepo = RepoRef(owner: 'demo', name: 'payments-api');

/// Workdir the mockup-mode FakeFileSystem is anchored at. Everything under
/// `${_mockupWorkdir}/jobs/pending/...` is seeded inside [_seedMockupFs].
const String _mockupWorkdir = '/mock';

/// Builds the composition root. Binds every port listed in §2.1's layer
/// diagram to either a real adapter (mode == real) or an in-memory fake
/// (mode == mockup). The returned scope wraps [child].
///
/// Test code doesn't call this — tests build their own [ProviderContainer]
/// or [ProviderScope] with per-test overrides.
ProviderScope buildAppScope({
  required AppMode mode,
  required Widget child,
}) {
  final overrides = switch (mode) {
    AppMode.real => _realOverrides(),
    AppMode.mockup => _mockupOverrides(),
  };
  return ProviderScope(overrides: overrides, child: child);
}

// ---------------------------------------------------------------------------
// Real-mode overrides
// ---------------------------------------------------------------------------

List<Override> _realOverrides() {
  final storage = KeystoreAdapter();
  final fs = FsAdapter();
  return [
    secureStorageProvider.overrideWithValue(storage),
    authPortProvider.overrideWithValue(
      GithubOAuthAdapter(clientId: _prodClientId, storage: storage),
    ),
    fileSystemProvider.overrideWithValue(fs),
    clockProvider.overrideWithValue(SystemClock()),
    idGeneratorProvider.overrideWithValue(SystemIdGenerator()),
    gitPortProvider.overrideWith((ref) {
      // Capture `ref` so the credentials loader stays lazy; resolving
      // storage at provider-define time would require a container which
      // Riverpod doesn't expose during factory construction. This closure
      // is invoked per remote op (clone/fetch/push), so reading the
      // token via `ref.read` each call picks up the latest session.
      return GitAdapter(
        credentialsLoader: () async =>
            ref.read(secureStorageProvider).readString(
                  SecureStorageKeys.authToken,
                ),
      );
    }),
    // Real mode has no picked repo/workdir yet; RepoPicker (M1c) sets them.
  ];
}

// ---------------------------------------------------------------------------
// Mockup-mode overrides
// ---------------------------------------------------------------------------

List<Override> _mockupOverrides() {
  final fs = FakeFileSystem();
  _seedMockupFs(fs);
  final auth = _buildMockupAuth();
  return [
    secureStorageProvider.overrideWithValue(FakeSecureStorage()),
    authPortProvider.overrideWithValue(auth),
    fileSystemProvider.overrideWithValue(fs),
    gitPortProvider.overrideWithValue(FakeGitPort()),
    clockProvider.overrideWithValue(SystemClock()),
    idGeneratorProvider.overrideWithValue(SystemIdGenerator()),
    currentWorkdirProvider.overrideWith((ref) => _mockupWorkdir),
    currentRepoProvider.overrideWith((ref) => _mockupRepo),
  ];
}

/// The fake identity used by the mockup-mode Sign In screen's auto-run
/// walkthrough. Both the Device Flow success path and the "known good"
/// PAT resolve to the same `(demo, demo@example.com)` pair.
const _mockupIdentity =
    GitIdentity(name: 'demo', email: 'demo@example.com');

/// The PAT the walkthrough documents as a "known good" token for the
/// Sign In screen's PAT fallback. Paired with an explicit invalid token
/// below so the dialog exercises both the success and error paths.
const _mockupDemoPat = 'ghp_mockup_demo_token';

/// Builds a [FakeAuthPort] seeded for the mockup browser:
///   * [FakeAuthPort.nextChallenge] — a realistic Device Flow challenge
///     so `AuthController.startDeviceFlow` surfaces a visible `userCode`
///     the reviewer can act on, instead of throwing `StateError`.
///   * [FakeAuthPort.pollScript] — two `PollAuthorizationPending`s then
///     a `PollSuccess`, so the awaiting-user → signed-in transition
///     auto-completes in ~3s during the walkthrough.
///   * [FakeAuthPort.patScript] — a known-good PAT that lands in
///     `AuthSignedIn`, plus a scripted bad token that emits
///     `AuthInvalidToken` so the dialog's error banner can be demoed.
FakeAuthPort _buildMockupAuth() {
  final session = const AuthSession(token: 'mock-token', identity: _mockupIdentity);
  return FakeAuthPort()
    ..nextChallenge = DeviceCodeChallenge(
      deviceCode: 'mock-device-code',
      userCode: 'WDJB-MJHT',
      verificationUri: 'https://github.com/login/device',
      pollInterval: const Duration(seconds: 1),
      expiresAt: DateTime.now().add(const Duration(minutes: 15)),
    )
    ..pollScript.addAll([
      const PollAuthorizationPending(),
      const PollAuthorizationPending(),
      PollSuccess(session),
    ])
    ..patScript.addAll({
      _mockupDemoPat: PatResponse.success(session),
      'ghp_mockup_bad_token':
          const PatResponse.error(AuthInvalidToken()),
    });
}

/// Pre-bakes the same three job folders the mockup JobListScreen used to
/// hold as an inline fixture. The literal filenames here map onto
/// `SpecRepository.listOpenJobs` so the controller-driven screen renders
/// the same three rows as before. Phase mapping:
///   spec-auth-flow-totp       → Phase.review (awaiting review, markdown)
///   spec-invoice-pdf-redesign → Phase.review (awaiting review, PDF)
///   spec-webhook-retry-policy → Phase.revised (awaiting revision, markdown)
void _seedMockupFs(FakeFileSystem fs) {
  const base = '$_mockupWorkdir/jobs/pending';
  fs
    ..seedFile(
      '$base/spec-auth-flow-totp/02-spec.md',
      '# TOTP rollout\n\n'
          'Open questions on magic-link fallback and refresh-token lifetime.\n',
    )
    ..seedFile(
      '$base/spec-auth-flow-totp/03-review.md',
      '# Review\n\nNotes pending.\n',
    )
    ..seedFile(
      '$base/spec-invoice-pdf-redesign/spec.pdf',
      // Short PDF-ish marker; FakeFileSystem doesn't validate content.
      '%PDF-1.4 mock',
    )
    ..seedFile(
      '$base/spec-invoice-pdf-redesign/03-review.md',
      '# Review\n\nLayout A vs B for the new PDF invoice template. '
          'Sample attached.\n',
    )
    ..seedFile(
      '$base/spec-webhook-retry-policy/02-spec.md',
      '# Webhook retry\n\nInitial spec.\n',
    )
    ..seedFile(
      '$base/spec-webhook-retry-policy/03-review.md',
      '# Review\n\nDead-letter behaviour.\n',
    )
    ..seedFile(
      '$base/spec-webhook-retry-policy/04-spec-v2.md',
      '# Webhook retry v2\n\nRevision v2 ready after review. '
          'Dead-letter behavior clarified.\n',
    );
}
