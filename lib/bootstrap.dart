import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/dev_seed.dart';
import 'app/providers/annotation_providers.dart';
import 'app/providers/auth_providers.dart';
import 'app/providers/pdf_providers.dart';
import 'app/providers/review_providers.dart';
import 'app/providers/spec_providers.dart';
import 'app/providers/sync_providers.dart';
import 'domain/entities/pointer_sample.dart';
import 'domain/ports/secure_storage_port.dart';
import 'infra/auth/github_oauth_adapter.dart';
import 'infra/clock/system_clock.dart';
import 'infra/fs/fs_adapter.dart';
import 'infra/git/git_adapter.dart';
import 'infra/id/system_id_generator.dart';
import 'infra/pdf/pdfx_adapter.dart';
import 'infra/png/png_flattener_adapter.dart';
import 'infra/storage/keystore_adapter.dart';

/// GitHub OAuth App client id for Device Flow. Public by design — ships
/// in the app binary. Security comes from GitHub-side user approval, not
/// from hiding this value.
const String _prodClientId = 'Ov23licdsOmS75Rq82SE';

/// Compile-time gate for the stylus-only palm-rejection rule. When built
/// with `--dart-define=ALLOW_MOUSE_ANNOTATION=true` the annotation canvas
/// also accepts mouse + touch events so the Android emulator (and future
/// desktop targets) can exercise ink flows without a real stylus. Tablet
/// release builds leave this unset and keep the production behavior.
const bool _kAllowMouseAnnotation = bool.fromEnvironment(
  'ALLOW_MOUSE_ANNOTATION',
);

const Set<PointerKind> _kDevPointerKinds = {
  PointerKind.stylus,
  PointerKind.mouse,
  PointerKind.touch,
};

/// Builds the composition root. Binds every port listed in §2.1's layer
/// diagram to its production adapter. The returned scope wraps [child].
///
/// When [devSeed] is non-null, additionally overrides
/// [currentWorkdirProvider] + [currentRepoProvider] so the JobList screen
/// has something to show before the real RepoPicker ships. Only set by
/// [prepareDevSeed] when `--dart-define=DEV_SEED_ENABLED=true`.
///
/// Test code doesn't call this — tests build their own [ProviderContainer]
/// or [ProviderScope] with per-test overrides.
ProviderScope buildAppScope({required Widget child, DevSeed? devSeed}) {
  final storage = KeystoreAdapter();
  final fs = FsAdapter();
  return ProviderScope(
    overrides: [
      secureStorageProvider.overrideWithValue(storage),
      authPortProvider.overrideWithValue(
        GithubOAuthAdapter(clientId: _prodClientId, storage: storage),
      ),
      fileSystemProvider.overrideWithValue(fs),
      clockProvider.overrideWithValue(SystemClock()),
      idGeneratorProvider.overrideWithValue(SystemIdGenerator()),
      pdfRasterPortProvider.overrideWithValue(PdfxAdapter()),
      pngFlattenerProvider.overrideWithValue(PngFlattenerAdapter()),
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
      // RepoPicker (M1c) sets currentWorkdirProvider + currentRepoProvider.
      if (devSeed != null) ...[
        currentWorkdirProvider.overrideWith((ref) => devSeed.workdir),
        currentRepoProvider.overrideWith((ref) => devSeed.repo),
      ],
      if (_kAllowMouseAnnotation)
        allowedPointerKindsProvider.overrideWithValue(_kDevPointerKinds),
    ],
    child: child,
  );
}
